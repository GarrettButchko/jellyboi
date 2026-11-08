//
//  AudioTranscodePipeline.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 10/14/26.
//

import Foundation
import LoggingKit
import Libavformat
import Libavcodec
import Libavutil
import Libswresample

// MARK: - Audio Transcode Pipeline

final class AudioTranscodePipeline {
    private var aDecCtx: UnsafeMutablePointer<AVCodecContext>?
    private var aEncCtx: UnsafeMutablePointer<AVCodecContext>?
    private var aSwrCtx: OpaquePointer?
    private var aFifo: OpaquePointer?
    private var decodedAudioFrame: UnsafeMutablePointer<AVFrame>?
    private var resampledAudioFrame: UnsafeMutablePointer<AVFrame>?
    private var outAudioFrame: UnsafeMutablePointer<AVFrame>?
    private var encAudioPkt: UnsafeMutablePointer<AVPacket>?

    private let outAudioStream: UnsafeMutablePointer<AVStream>
    private let outAudioIdx: Int32
    private let writePacket: (UnsafeMutablePointer<AVPacket>) throws -> Void

    private var nextAudioPts: Int64 = 0
    private var aFrameSize: Int = 1024

    // MARK: - Static Codec Support Helpers

    static func isSupportedAudioCodec(_ codecID: AVCodecID) -> Bool {
        return codecID == AV_CODEC_ID_AAC ||
               codecID == AV_CODEC_ID_ALAC
    }

    // MARK: - Initialization

    init(
        inAudioStream: UnsafeMutablePointer<AVStream>,
        outAudioStream: UnsafeMutablePointer<AVStream>,
        outCtx: UnsafeMutablePointer<AVFormatContext>,
        outAudioIdx: Int32,
        writePacket: @escaping (UnsafeMutablePointer<AVPacket>) throws -> Void
    ) throws {
        self.outAudioStream = outAudioStream
        self.outAudioIdx = outAudioIdx
        self.writePacket = writePacket

        // 1. Initialize audio decoder
        let inCodecPar = inAudioStream.pointee.codecpar.pointee
        guard let aDecoder = avcodec_find_decoder(inCodecPar.codec_id) else {
            let codecName = String(cString: avcodec_get_name(inCodecPar.codec_id))
            throw RemuxError.unsupportedAudioCodec("No decoder available for \(codecName)")
        }
        guard let adCtx = avcodec_alloc_context3(aDecoder) else {
            throw RemuxError.createOutputContextFailed
        }
        self.aDecCtx = adCtx
        var ret = avcodec_parameters_to_context(adCtx, inAudioStream.pointee.codecpar)
        guard ret >= 0 else { throw RemuxError.copyCodecParametersFailed(ret) }
        ret = avcodec_open2(adCtx, aDecoder, nil)
        guard ret >= 0 else { throw RemuxError.openDecoderFailed(ret) }

        // 2. Initialize AAC audio encoder
        guard let aEncoder = avcodec_find_encoder(AV_CODEC_ID_AAC) else {
            throw RemuxError.unsupportedAudioCodec("AAC audio encoder not available")
        }
        guard let aeCtx = avcodec_alloc_context3(aEncoder) else {
            throw RemuxError.createOutputContextFailed
        }
        self.aEncCtx = aeCtx

        let outSampleRate = adCtx.pointee.sample_rate > 0 ? adCtx.pointee.sample_rate : 48000
        aeCtx.pointee.sample_rate = outSampleRate
        aeCtx.pointee.sample_fmt = AV_SAMPLE_FMT_FLTP
        aeCtx.pointee.bit_rate = 192_000
        aeCtx.pointee.time_base = AVRational(num: 1, den: outSampleRate)
        av_channel_layout_default(&aeCtx.pointee.ch_layout, 2)

        if (outCtx.pointee.oformat.pointee.flags & AVFMT_GLOBALHEADER) != 0 {
            aeCtx.pointee.flags |= AV_CODEC_FLAG_GLOBAL_HEADER
        }

        ret = avcodec_open2(aeCtx, aEncoder, nil)
        guard ret >= 0 else { throw RemuxError.openEncoderFailed(ret) }

        ret = avcodec_parameters_from_context(outAudioStream.pointee.codecpar, aeCtx)
        guard ret >= 0 else { throw RemuxError.copyCodecParametersFailed(ret) }
        outAudioStream.pointee.time_base = aeCtx.pointee.time_base
        outAudioStream.pointee.codecpar.pointee.codec_tag = 0

        // 3. Configure audio resampler (SwrContext)
        var inLayout = AVChannelLayout()
        if adCtx.pointee.ch_layout.nb_channels > 0 {
            _ = av_channel_layout_copy(&inLayout, &adCtx.pointee.ch_layout)
        } else {
            av_channel_layout_default(&inLayout, 2)
        }
        defer {
            av_channel_layout_uninit(&inLayout)
        }

        var swr: OpaquePointer? = nil
        ret = swr_alloc_set_opts2(
            &swr,
            &aeCtx.pointee.ch_layout,
            aeCtx.pointee.sample_fmt,
            aeCtx.pointee.sample_rate,
            &inLayout,
            adCtx.pointee.sample_fmt,
            adCtx.pointee.sample_rate,
            0,
            nil
        )
        guard ret >= 0, let validSwr = swr else {
            throw RemuxError.openDecoderFailed(ret)
        }
        ret = swr_init(validSwr)
        guard ret >= 0 else {
            throw RemuxError.openDecoderFailed(ret)
        }
        self.aSwrCtx = validSwr

        // 4. Configure audio FIFO buffer
        self.aFrameSize = aeCtx.pointee.frame_size > 0 ? Int(aeCtx.pointee.frame_size) : 1024
        guard let fifo = av_audio_fifo_alloc(aeCtx.pointee.sample_fmt, 2, Int32(aFrameSize * 4)) else {
            throw RemuxError.allocateFrameFailed
        }
        self.aFifo = fifo

        // 5. Pre-allocate audio frames & packet
        self.decodedAudioFrame = av_frame_alloc()
        self.resampledAudioFrame = av_frame_alloc()
        self.outAudioFrame = av_frame_alloc()
        self.encAudioPkt = av_packet_alloc()

        guard decodedAudioFrame != nil,
              resampledAudioFrame != nil,
              let oaf = outAudioFrame,
              encAudioPkt != nil else {
            throw RemuxError.allocateFrameFailed
        }

        oaf.pointee.nb_samples = Int32(aFrameSize)
        oaf.pointee.format = aeCtx.pointee.sample_fmt.rawValue
        oaf.pointee.sample_rate = aeCtx.pointee.sample_rate
        _ = av_channel_layout_copy(&oaf.pointee.ch_layout, &aeCtx.pointee.ch_layout)
        let bufRet = av_frame_get_buffer(oaf, 0)
        guard bufRet >= 0 else {
            throw RemuxError.allocateFrameFailed
        }

        AppLogger.info("Mapped input audio -> output MP4 track #\(outAudioIdx) [Transcoding \(inCodecPar.sample_rate)Hz to AAC stereo 192k]")
    }

    deinit {
        avcodec_free_context(&aDecCtx)
        avcodec_free_context(&aEncCtx)
        swr_free(&aSwrCtx)
        if let fifo = aFifo {
            av_audio_fifo_free(fifo)
        }
        av_frame_free(&decodedAudioFrame)
        av_frame_free(&resampledAudioFrame)
        av_frame_free(&outAudioFrame)
        av_packet_free(&encAudioPkt)
    }

    // MARK: - FIFO Helpers

    private static func writeFrameToAudioFifo(fifo: OpaquePointer, frame: UnsafeMutablePointer<AVFrame>) -> Int32 {
        let nbSamples = frame.pointee.nb_samples
        guard nbSamples > 0 else { return 0 }
        let curSize = av_audio_fifo_size(fifo)
        let reallocRet = av_audio_fifo_realloc(fifo, curSize + nbSamples)
        if reallocRet < 0 { return reallocRet }

        var planes: [UnsafeMutableRawPointer?] = [
            UnsafeMutableRawPointer(frame.pointee.data.0),
            UnsafeMutableRawPointer(frame.pointee.data.1)
        ]
        return planes.withUnsafeMutableBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return -1 }
            return av_audio_fifo_write(fifo, base, nbSamples)
        }
    }

    private static func readFrameFromAudioFifo(fifo: OpaquePointer, frame: UnsafeMutablePointer<AVFrame>, nbSamples: Int32) -> Int32 {
        var planes: [UnsafeMutableRawPointer?] = [
            UnsafeMutableRawPointer(frame.pointee.data.0),
            UnsafeMutableRawPointer(frame.pointee.data.1)
        ]
        return planes.withUnsafeMutableBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return -1 }
            return av_audio_fifo_read(fifo, base, nbSamples)
        }
    }

    private static func padAudioFrameWithSilence(frame: UnsafeMutablePointer<AVFrame>, offset: Int32, nbSamples: Int32) {
        guard nbSamples > 0 else { return }
        var planes: [UnsafeMutablePointer<UInt8>?] = [
            frame.pointee.data.0,
            frame.pointee.data.1
        ]
        planes.withUnsafeMutableBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            _ = av_samples_set_silence(base, offset, nbSamples, 2, AV_SAMPLE_FMT_FLTP)
        }
    }

    // MARK: - Processing & Draining

    func process(packet: UnsafeMutablePointer<AVPacket>) throws {
        guard let adCtx = aDecCtx,
              let aeCtx = aEncCtx,
              let swr = aSwrCtx,
              let fifo = aFifo,
              let dAudioFrame = decodedAudioFrame,
              let rAudioFrame = resampledAudioFrame else { return }

        let ret = avcodec_send_packet(adCtx, packet)
        guard ret >= 0 else { return }

        while avcodec_receive_frame(adCtx, dAudioFrame) >= 0 {
            av_frame_unref(rAudioFrame)
            rAudioFrame.pointee.format = aeCtx.pointee.sample_fmt.rawValue
            rAudioFrame.pointee.sample_rate = aeCtx.pointee.sample_rate
            _ = av_channel_layout_copy(&rAudioFrame.pointee.ch_layout, &aeCtx.pointee.ch_layout)

            var convRet = swr_convert_frame(swr, rAudioFrame, dAudioFrame)
            if convRet < 0 {
                _ = swr_config_frame(swr, rAudioFrame, dAudioFrame)
                _ = swr_init(swr)
                convRet = swr_convert_frame(swr, rAudioFrame, dAudioFrame)
            }

            if convRet >= 0 && rAudioFrame.pointee.nb_samples > 0 {
                _ = Self.writeFrameToAudioFifo(fifo: fifo, frame: rAudioFrame)
            }
            av_frame_unref(dAudioFrame)

            try encodeAvailableFifoChunks()
        }
    }

    private func encodeAvailableFifoChunks() throws {
        guard let fifo = aFifo,
              let oaf = outAudioFrame,
              let aeCtx = aEncCtx,
              let ePkt = encAudioPkt else { return }

        while av_audio_fifo_size(fifo) >= Int32(aFrameSize) {
            _ = av_frame_make_writable(oaf)
            _ = Self.readFrameFromAudioFifo(fifo: fifo, frame: oaf, nbSamples: Int32(aFrameSize))
            oaf.pointee.nb_samples = Int32(aFrameSize)
            oaf.pointee.pts = nextAudioPts
            nextAudioPts += Int64(aFrameSize)

            let ret = avcodec_send_frame(aeCtx, oaf)
            if ret >= 0 {
                while avcodec_receive_packet(aeCtx, ePkt) >= 0 {
                    av_packet_rescale_ts(ePkt, aeCtx.pointee.time_base, outAudioStream.pointee.time_base)
                    ePkt.pointee.stream_index = outAudioIdx
                    ePkt.pointee.pos = -1
                    try writePacket(ePkt)
                    av_packet_unref(ePkt)
                }
            }
        }
    }

    func flush() throws {
        guard let adCtx = aDecCtx,
              let aeCtx = aEncCtx,
              let swr = aSwrCtx,
              let fifo = aFifo,
              let dAudioFrame = decodedAudioFrame,
              let rAudioFrame = resampledAudioFrame,
              let oaf = outAudioFrame,
              let ePkt = encAudioPkt else { return }

        // 1. Drain decoder
        var ret = avcodec_send_packet(adCtx, nil)
        if ret >= 0 {
            while avcodec_receive_frame(adCtx, dAudioFrame) >= 0 {
                av_frame_unref(rAudioFrame)
                rAudioFrame.pointee.format = aeCtx.pointee.sample_fmt.rawValue
                rAudioFrame.pointee.sample_rate = aeCtx.pointee.sample_rate
                _ = av_channel_layout_copy(&rAudioFrame.pointee.ch_layout, &aeCtx.pointee.ch_layout)

                let convRet = swr_convert_frame(swr, rAudioFrame, dAudioFrame)
                if convRet >= 0 && rAudioFrame.pointee.nb_samples > 0 {
                    _ = Self.writeFrameToAudioFifo(fifo: fifo, frame: rAudioFrame)
                }
                av_frame_unref(dAudioFrame)
            }
        }

        // 2. Flush SwrContext internal delay buffer
        while true {
            av_frame_unref(rAudioFrame)
            rAudioFrame.pointee.format = aeCtx.pointee.sample_fmt.rawValue
            rAudioFrame.pointee.sample_rate = aeCtx.pointee.sample_rate
            _ = av_channel_layout_copy(&rAudioFrame.pointee.ch_layout, &aeCtx.pointee.ch_layout)

            let convRet = swr_convert_frame(swr, rAudioFrame, nil)
            if convRet < 0 || rAudioFrame.pointee.nb_samples <= 0 {
                break
            }
            _ = Self.writeFrameToAudioFifo(fifo: fifo, frame: rAudioFrame)
        }
        av_frame_unref(rAudioFrame)

        // 3. Drain FIFO (pad trailing partial frame with silence)
        while av_audio_fifo_size(fifo) > 0 {
            let pendingSamples = min(av_audio_fifo_size(fifo), Int32(aFrameSize))
            _ = av_frame_make_writable(oaf)
            _ = Self.readFrameFromAudioFifo(fifo: fifo, frame: oaf, nbSamples: pendingSamples)
            if pendingSamples < Int32(aFrameSize) {
                Self.padAudioFrameWithSilence(frame: oaf, offset: pendingSamples, nbSamples: Int32(aFrameSize) - pendingSamples)
            }
            oaf.pointee.nb_samples = Int32(aFrameSize)
            oaf.pointee.pts = nextAudioPts
            nextAudioPts += Int64(aFrameSize)

            ret = avcodec_send_frame(aeCtx, oaf)
            if ret >= 0 {
                while avcodec_receive_packet(aeCtx, ePkt) >= 0 {
                    av_packet_rescale_ts(ePkt, aeCtx.pointee.time_base, outAudioStream.pointee.time_base)
                    ePkt.pointee.stream_index = outAudioIdx
                    ePkt.pointee.pos = -1
                    try writePacket(ePkt)
                    av_packet_unref(ePkt)
                }
            }
        }

        // 4. Drain audio encoder
        ret = avcodec_send_frame(aeCtx, nil)
        if ret >= 0 {
            while avcodec_receive_packet(aeCtx, ePkt) >= 0 {
                av_packet_rescale_ts(ePkt, aeCtx.pointee.time_base, outAudioStream.pointee.time_base)
                ePkt.pointee.stream_index = outAudioIdx
                ePkt.pointee.pos = -1
                try writePacket(ePkt)
                av_packet_unref(ePkt)
            }
        }
    }
}
