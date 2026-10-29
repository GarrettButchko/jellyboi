//
//  VideoTranscodePipeline.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 10/14/26.
//

import Foundation
import LoggingKit
import Libavformat
import Libavcodec
import Libavutil
import Libswscale

// MARK: - Video Transcode Pipeline

final class VideoTranscodePipeline {
    private let avNoPtsValue: Int64 = Int64.min
    private var decCtx: UnsafeMutablePointer<AVCodecContext>?
    private var encCtx: UnsafeMutablePointer<AVCodecContext>?
    private var swsCtx: UnsafeMutablePointer<SwsContext>?
    private var decodedFrame: UnsafeMutablePointer<AVFrame>?
    private var scaledFrame: UnsafeMutablePointer<AVFrame>?
    private var encPkt: UnsafeMutablePointer<AVPacket>?

    private let inTimeBase: AVRational
    private let outVideoStream: UnsafeMutablePointer<AVStream>
    private let outVideoIdx: Int32
    private let writePacket: (UnsafeMutablePointer<AVPacket>) throws -> Void

    private var lastVideoPts: Int64 = -1
    private(set) var videoFrameCount: Int64 = 0

    // MARK: - Static Codec Support Helpers

    static func isSupportedVideoCodec(_ codecID: AVCodecID) -> Bool {
        return codecID == AV_CODEC_ID_H264 ||
               codecID == AV_CODEC_ID_HEVC ||
               codecID == AV_CODEC_ID_MPEG4 ||
               codecID == AV_CODEC_ID_AV1 ||
               codecID == AV_CODEC_ID_PRORES
    }

    static func findCompatibleVideoEncoder() -> UnsafePointer<AVCodec>? {
        if let enc = avcodec_find_encoder_by_name("h264_videotoolbox") {
            AppLogger.info("Selected hardware video encoder: h264_videotoolbox", tag: "Remuxer")
            return enc
        }
        if let enc = avcodec_find_encoder(AV_CODEC_ID_H264) {
            AppLogger.info("Selected video encoder: \(String(cString: enc.pointee.name))", tag: "Remuxer")
            return enc
        }
        if let enc = avcodec_find_encoder_by_name("hevc_videotoolbox") {
            AppLogger.info("Selected hardware video encoder: hevc_videotoolbox", tag: "Remuxer")
            return enc
        }
        if let enc = avcodec_find_encoder(AV_CODEC_ID_MPEG4) {
            AppLogger.info("Selected video encoder: mpeg4", tag: "Remuxer")
            return enc
        }
        return nil
    }

    // MARK: - Initialization

    init(
        inVideoStream: UnsafeMutablePointer<AVStream>,
        outVideoStream: UnsafeMutablePointer<AVStream>,
        outCtx: UnsafeMutablePointer<AVFormatContext>,
        outVideoIdx: Int32,
        effectiveSAR: AVRational,
        writePacket: @escaping (UnsafeMutablePointer<AVPacket>) throws -> Void
    ) throws {
        self.inTimeBase = inVideoStream.pointee.time_base
        self.outVideoStream = outVideoStream
        self.outVideoIdx = outVideoIdx
        self.writePacket = writePacket

        // 1. Initialize video decoder
        let inCodecPar = inVideoStream.pointee.codecpar.pointee
        guard let decoder = avcodec_find_decoder(inCodecPar.codec_id) else {
            let codecName = String(cString: avcodec_get_name(inCodecPar.codec_id))
            throw RemuxError.unsupportedVideoCodec("No decoder available for \(codecName)")
        }
        guard let dCtx = avcodec_alloc_context3(decoder) else {
            throw RemuxError.createOutputContextFailed
        }
        self.decCtx = dCtx
        var ret = avcodec_parameters_to_context(dCtx, inVideoStream.pointee.codecpar)
        guard ret >= 0 else { throw RemuxError.copyCodecParametersFailed(ret) }
        ret = avcodec_open2(dCtx, decoder, nil)
        guard ret >= 0 else { throw RemuxError.openDecoderFailed(ret) }

        // 2. Initialize video encoder
        guard let encoder = Self.findCompatibleVideoEncoder() else {
            throw RemuxError.unsupportedVideoCodec("No suitable video encoder found on device")
        }
        guard let eCtx = avcodec_alloc_context3(encoder) else {
            throw RemuxError.createOutputContextFailed
        }
        self.encCtx = eCtx

        eCtx.pointee.width = inCodecPar.width
        eCtx.pointee.height = inCodecPar.height

        let framerate: AVRational = {
            if inVideoStream.pointee.r_frame_rate.num > 0 && inVideoStream.pointee.r_frame_rate.den > 0 {
                return inVideoStream.pointee.r_frame_rate
            }
            if inVideoStream.pointee.avg_frame_rate.num > 0 && inVideoStream.pointee.avg_frame_rate.den > 0 {
                return inVideoStream.pointee.avg_frame_rate
            }
            return AVRational(num: 30, den: 1)
        }()
        eCtx.pointee.framerate = framerate
        eCtx.pointee.time_base = AVRational(num: framerate.den, den: framerate.num)

        let targetPixFmt: AVPixelFormat = (encoder.pointee.id == AV_CODEC_ID_H264 || encoder.pointee.id == AV_CODEC_ID_HEVC) ? AV_PIX_FMT_NV12 : AV_PIX_FMT_YUV420P
        eCtx.pointee.pix_fmt = targetPixFmt

        let estimatedBitrate: Int64 = {
            let pixels = Int64(eCtx.pointee.width * eCtx.pointee.height)
            if pixels <= 720 * 480 {
                return 2_500_000
            } else if pixels <= 1280 * 720 {
                return 4_500_000
            } else {
                return 8_000_000
            }
        }()
        let targetBitrate = (inCodecPar.bit_rate > 500_000 && inCodecPar.bit_rate < 25_000_000)
            ? inCodecPar.bit_rate
            : estimatedBitrate
        eCtx.pointee.bit_rate = targetBitrate
        eCtx.pointee.gop_size = Int32(max(1, Int(framerate.num / max(1, framerate.den)) * 2))

        eCtx.pointee.sample_aspect_ratio = effectiveSAR

        if (outCtx.pointee.oformat.pointee.flags & AVFMT_GLOBALHEADER) != 0 {
            eCtx.pointee.flags |= AV_CODEC_FLAG_GLOBAL_HEADER
        }

        var encOpts: OpaquePointer? = nil
        av_dict_set(&encOpts, "realtime", "0", 0)
        av_dict_set(&encOpts, "allow_sw", "1", 0)
        ret = avcodec_open2(eCtx, encoder, &encOpts)
        av_dict_free(&encOpts)
        guard ret >= 0 else {
            throw RemuxError.openEncoderFailed(ret)
        }

        ret = avcodec_parameters_from_context(outVideoStream.pointee.codecpar, eCtx)
        guard ret >= 0 else { throw RemuxError.copyCodecParametersFailed(ret) }
        outVideoStream.pointee.time_base = eCtx.pointee.time_base
        outVideoStream.pointee.r_frame_rate = eCtx.pointee.framerate
        outVideoStream.pointee.avg_frame_rate = eCtx.pointee.framerate
        outVideoStream.pointee.sample_aspect_ratio = effectiveSAR
        outVideoStream.pointee.codecpar.pointee.sample_aspect_ratio = effectiveSAR

        let encoderID = eCtx.pointee.codec_id
        if encoderID == AV_CODEC_ID_HEVC {
            let hvc1Tag: UInt32 = UInt32(UInt8(ascii: "h")) |
                                  (UInt32(UInt8(ascii: "v")) << 8) |
                                  (UInt32(UInt8(ascii: "c")) << 16) |
                                  (UInt32(UInt8(ascii: "1")) << 24)
            outVideoStream.pointee.codecpar.pointee.codec_tag = hvc1Tag
        } else {
            outVideoStream.pointee.codecpar.pointee.codec_tag = 0
        }

        // 3. Setup swscale if pixel format or dimensions differ
        let needsScale = (dCtx.pointee.pix_fmt != eCtx.pointee.pix_fmt) ||
                         (dCtx.pointee.width != eCtx.pointee.width) ||
                         (dCtx.pointee.height != eCtx.pointee.height)

        if needsScale {
            if let rawSws = sws_getContext(
                dCtx.pointee.width,
                dCtx.pointee.height,
                dCtx.pointee.pix_fmt,
                eCtx.pointee.width,
                eCtx.pointee.height,
                eCtx.pointee.pix_fmt,
                Int32(SWS_BILINEAR.rawValue),
                nil, nil, nil
            ) {
                self.swsCtx = UnsafeMutablePointer<SwsContext>(rawSws)
            }
            self.scaledFrame = av_frame_alloc()
            guard let sf = self.scaledFrame else { throw RemuxError.allocateFrameFailed }
            sf.pointee.format = eCtx.pointee.pix_fmt.rawValue
            sf.pointee.width = eCtx.pointee.width
            sf.pointee.height = eCtx.pointee.height
            let bufRet = av_frame_get_buffer(sf, 32)
            guard bufRet >= 0 else { throw RemuxError.allocateFrameFailed }
        }

        self.decodedFrame = av_frame_alloc()
        self.encPkt = av_packet_alloc()
        guard self.decodedFrame != nil, self.encPkt != nil else {
            throw RemuxError.allocateFrameFailed
        }

        AppLogger.info("Mapped input video -> output MP4 track #\(outVideoIdx) [Transcoding \(inCodecPar.width)x\(inCodecPar.height) to \(String(cString: encoder.pointee.name))]", tag: "Remuxer")
    }

    deinit {
        avcodec_free_context(&decCtx)
        avcodec_free_context(&encCtx)
        if let swsCtx {
            sws_freeContext(swsCtx)
        }
        av_frame_free(&decodedFrame)
        av_frame_free(&scaledFrame)
        av_packet_free(&encPkt)
    }

    // MARK: - Processing & Draining

    func process(
        packet: UnsafeMutablePointer<AVPacket>,
        onFrameDecoded: ((_ rawPts: Int64) -> Void)? = nil
    ) throws {
        guard let decCtx, let encCtx, let decodedFrame, let encPkt else { return }

        let ret = avcodec_send_packet(decCtx, packet)
        guard ret >= 0 else { return }

        while avcodec_receive_frame(decCtx, decodedFrame) >= 0 {
            try encodeAndWriteFrame(decodedFrame: decodedFrame, encCtx: encCtx, encPkt: encPkt)
            videoFrameCount += 1

            let rawPts = (decodedFrame.pointee.pts != avNoPtsValue) ? decodedFrame.pointee.pts : decodedFrame.pointee.best_effort_timestamp
            onFrameDecoded?(rawPts)
            av_frame_unref(decodedFrame)
        }
    }

    private func encodeAndWriteFrame(
        decodedFrame: UnsafeMutablePointer<AVFrame>,
        encCtx: UnsafeMutablePointer<AVCodecContext>,
        encPkt: UnsafeMutablePointer<AVPacket>
    ) throws {
        let frameToEncode: UnsafeMutablePointer<AVFrame>
        let rawPts = (decodedFrame.pointee.pts != avNoPtsValue) ? decodedFrame.pointee.pts : decodedFrame.pointee.best_effort_timestamp
        let computedPts: Int64 = (rawPts != avNoPtsValue)
            ? av_rescale_q(rawPts, inTimeBase, encCtx.pointee.time_base)
            : (lastVideoPts + 1)
        let safePts = max(computedPts, lastVideoPts + 1)
        lastVideoPts = safePts

        if let sws = swsCtx, let sf = scaledFrame {
            _ = av_frame_make_writable(sf)
            _ = sws_scale_frame(sws, sf, decodedFrame)
            sf.pointee.pts = safePts
            sf.pointee.duration = av_rescale_q(decodedFrame.pointee.duration, inTimeBase, encCtx.pointee.time_base)
            frameToEncode = sf
        } else {
            decodedFrame.pointee.pts = safePts
            frameToEncode = decodedFrame
        }

        let ret = avcodec_send_frame(encCtx, frameToEncode)
        guard ret >= 0 else { return }

        while avcodec_receive_packet(encCtx, encPkt) >= 0 {
            av_packet_rescale_ts(encPkt, encCtx.pointee.time_base, outVideoStream.pointee.time_base)
            encPkt.pointee.stream_index = outVideoIdx
            encPkt.pointee.pos = -1
            try writePacket(encPkt)
            av_packet_unref(encPkt)
        }
    }

    func flush() throws {
        guard let decCtx, let encCtx, let decodedFrame, let encPkt else { return }

        // 1. Drain decoder
        var ret = avcodec_send_packet(decCtx, nil)
        if ret >= 0 {
            while avcodec_receive_frame(decCtx, decodedFrame) >= 0 {
                try encodeAndWriteFrame(decodedFrame: decodedFrame, encCtx: encCtx, encPkt: encPkt)
                videoFrameCount += 1
                av_frame_unref(decodedFrame)
            }
        }

        // 2. Drain encoder
        ret = avcodec_send_frame(encCtx, nil)
        if ret >= 0 {
            while avcodec_receive_packet(encCtx, encPkt) >= 0 {
                av_packet_rescale_ts(encPkt, encCtx.pointee.time_base, outVideoStream.pointee.time_base)
                encPkt.pointee.stream_index = outVideoIdx
                encPkt.pointee.pos = -1
                try writePacket(encPkt)
                av_packet_unref(encPkt)
            }
        }
    }
}
