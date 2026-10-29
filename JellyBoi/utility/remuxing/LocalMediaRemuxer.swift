//
//  LocalMediaRemuxer.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 10/14/26.
//

import Foundation
import LoggingKit
import Libavformat
import Libavcodec
import Libavutil

// MARK: - Local Media Remuxer

public enum LocalMediaRemuxer {
    private static let avNoPtsValue: Int64 = Int64.min
    private static let backgroundQueue = DispatchQueue(
        label: "com.jellyboi.LocalMediaRemuxer",
        qos: .utility
    )

    /// Asynchronously runs media remuxing/transcoding on a dedicated background queue to avoid blocking
    /// the main UI thread or saturating the Swift Concurrency cooperative thread pool.
    public static func remuxToMP4Async(
        inputURL: URL,
        outputURL: URL,
        targetAspectRatio: String? = nil,
        progressHandler: (@Sendable (Double) -> Void)? = nil
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            backgroundQueue.async {
                do {
                    try remuxToMP4(
                        inputURL: inputURL,
                        outputURL: outputURL,
                        targetAspectRatio: targetAspectRatio,
                        progressHandler: progressHandler
                    )
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    public static func remuxToMP4(
        inputURL: URL,
        outputURL: URL,
        targetAspectRatio: String? = nil,
        progressHandler: (@Sendable (Double) -> Void)? = nil
    ) throws {
        #if DEBUG
        if Thread.isMainThread {
            AppLogger.warning("LocalMediaRemuxer.remuxToMP4 was called directly on the main thread! Use remuxToMP4Async or a background thread to prevent UI freezing.", tag: "Remuxer")
        }
        if DebugSettings.shared.simulateRemuxFailure {
            AppLogger.warning("[DebugSettings] Simulating remux failure", tag: "Remuxer")
            throw RemuxError.unsupportedVideoCodec("Simulated failure via DebugSettings")
        }
        #endif

        var lastReportedTime: CFAbsoluteTime = 0
        var lastReportedPercent: Int = -1

        let reportProgress: (Double) -> Void = { p in
            guard let progressHandler else { return }
            let now = CFAbsoluteTimeGetCurrent()
            let percent = Int(p * 100)
            if now - lastReportedTime >= 0.25 || (percent != lastReportedPercent && now - lastReportedTime >= 0.1) {
                lastReportedTime = now
                lastReportedPercent = percent
                progressHandler(p)
            }
        }

        var ifmt_ctx: UnsafeMutablePointer<AVFormatContext>? = nil
        var ofmt_ctx: UnsafeMutablePointer<AVFormatContext>? = nil

        var ret = avformat_open_input(&ifmt_ctx, inputURL.path, nil, nil)
        guard ret >= 0, let inCtx = ifmt_ctx else {
            throw RemuxError.openInputFailed(ret)
        }
        defer {
            avformat_close_input(&ifmt_ctx)
        }

        ret = avformat_find_stream_info(inCtx, nil)
        guard ret >= 0 else {
            throw RemuxError.findStreamInfoFailed(ret)
        }

        ret = avformat_alloc_output_context2(&ofmt_ctx, nil, "mp4", outputURL.path)
        guard ret >= 0, let outCtx = ofmt_ctx else {
            throw RemuxError.createOutputContextFailed
        }
        defer {
            if outCtx.pointee.pb != nil {
                avio_closep(&outCtx.pointee.pb)
            }
            avformat_free_context(outCtx)
        }

        let nbStreams = Int(inCtx.pointee.nb_streams)
        AppLogger.info("Analyzing container: \(nbStreams) streams found", tag: "Remuxer")

        var videoIndices: [Int] = []
        var audioIndices: [Int] = []

        for i in 0..<nbStreams {
            guard let inStream = inCtx.pointee.streams[i]?.pointee,
                  let inCodecPar = inStream.codecpar?.pointee else { continue }
            let codecName = String(cString: avcodec_get_name(inCodecPar.codec_id))
            let isVideo = inCodecPar.codec_type == AVMEDIA_TYPE_VIDEO
            let isAudio = inCodecPar.codec_type == AVMEDIA_TYPE_AUDIO

            if isVideo {
                videoIndices.append(i)
                AppLogger.info("Source stream #\(i) [VIDEO]: codec=\(codecName), \(inCodecPar.width)x\(inCodecPar.height), extradata=\(inCodecPar.extradata_size)b, tb=\(inStream.time_base.num)/\(inStream.time_base.den)", tag: "Remuxer")
            } else if isAudio {
                audioIndices.append(i)
                AppLogger.info("Source stream #\(i) [AUDIO]: codec=\(codecName), \(inCodecPar.sample_rate)Hz, ch=\(inCodecPar.ch_layout.nb_channels), tb=\(inStream.time_base.num)/\(inStream.time_base.den)", tag: "Remuxer")
            } else {
                AppLogger.debug("Source stream #\(i) [OTHER]: type=\(inCodecPar.codec_type.rawValue), codec=\(codecName)", tag: "Remuxer")
            }
        }

        guard !videoIndices.isEmpty || !audioIndices.isEmpty else {
            throw RemuxError.noCompatibleStreams
        }

        let primaryVideoInIdx: Int? = videoIndices.first
        let primaryAudioInIdx: Int? = audioIndices.first

        // Determine if video needs transcoding
        var needsVideoTranscode = false
        if let vIdx = primaryVideoInIdx,
           let cp = inCtx.pointee.streams[vIdx]?.pointee.codecpar?.pointee {
            needsVideoTranscode = !VideoTranscodePipeline.isSupportedVideoCodec(cp.codec_id)
            let codecName = String(cString: avcodec_get_name(cp.codec_id))
            if needsVideoTranscode {
                AppLogger.info("Video codec '\(codecName)' is not natively supported in MP4 for AVPlayer; hardware transcoding to H.264 enabled", tag: "Remuxer")
            } else {
                AppLogger.info("Video codec '\(codecName)' is natively supported; using fast stream copy", tag: "Remuxer")
            }
        }

        // Determine if audio needs transcoding
        var needsAudioTranscode = false
        if let aIdx = primaryAudioInIdx,
           let cp = inCtx.pointee.streams[aIdx]?.pointee.codecpar?.pointee {
            needsAudioTranscode = !AudioTranscodePipeline.isSupportedAudioCodec(cp.codec_id)
            let codecName = String(cString: avcodec_get_name(cp.codec_id))
            if needsAudioTranscode {
                AppLogger.info("Audio codec '\(codecName)' is not natively supported in MP4 for AVPlayer; transcoding to AAC enabled", tag: "Remuxer")
            } else {
                AppLogger.info("Audio codec '\(codecName)' is natively supported; using fast stream copy", tag: "Remuxer")
            }
        }

        var streamMapping = [Int32](repeating: -1, count: nbStreams)
        var nextOutIdx: Int32 = 0
        var outVideoIdx: Int32 = -1
        var outAudioIdx: Int32 = -1

        var videoPipeline: VideoTranscodePipeline? = nil
        var audioPipeline: AudioTranscodePipeline? = nil

        var videoPacketsWritten = 0
        var audioPacketsWritten = 0

        let writePacketSafely: (UnsafeMutablePointer<AVPacket>) throws -> Void = { packet in
            let writeRet = av_interleaved_write_frame(outCtx, packet)
            guard writeRet >= 0 else {
                throw RemuxError.writeFrameFailed(writeRet)
            }
        }

        // 1. Setup Video Output Stream (Track 0)
        if let vInIdx = primaryVideoInIdx,
           let inVideoStream = inCtx.pointee.streams[vInIdx] {
            guard let outVideoStream = avformat_new_stream(outCtx, nil) else {
                throw RemuxError.createStreamFailed
            }
            outVideoIdx = nextOutIdx
            streamMapping[vInIdx] = outVideoIdx
            nextOutIdx += 1

            let effectiveSAR = RemuxAspectRatioHelper.resolveEffectiveSAR(
                inCtx: inCtx,
                inVideoStream: inVideoStream,
                targetAspectRatio: targetAspectRatio
            )

            if !needsVideoTranscode {
                // Direct stream copy
                ret = avcodec_parameters_copy(outVideoStream.pointee.codecpar, inVideoStream.pointee.codecpar)
                guard ret >= 0 else { throw RemuxError.copyCodecParametersFailed(ret) }
                outVideoStream.pointee.time_base = inVideoStream.pointee.time_base
                outVideoStream.pointee.r_frame_rate = inVideoStream.pointee.r_frame_rate
                outVideoStream.pointee.avg_frame_rate = inVideoStream.pointee.avg_frame_rate
                outVideoStream.pointee.sample_aspect_ratio = effectiveSAR
                outVideoStream.pointee.codecpar.pointee.sample_aspect_ratio = effectiveSAR

                let codecID = outVideoStream.pointee.codecpar.pointee.codec_id
                if codecID == AV_CODEC_ID_HEVC {
                    let hvc1Tag: UInt32 = UInt32(UInt8(ascii: "h")) |
                                          (UInt32(UInt8(ascii: "v")) << 8) |
                                          (UInt32(UInt8(ascii: "c")) << 16) |
                                          (UInt32(UInt8(ascii: "1")) << 24)
                    outVideoStream.pointee.codecpar.pointee.codec_tag = hvc1Tag
                } else {
                    outVideoStream.pointee.codecpar.pointee.codec_tag = 0
                }
                AppLogger.info("Mapped input video #\(vInIdx) -> output MP4 track #\(outVideoIdx) [Direct Copy]", tag: "Remuxer")
            } else {
                videoPipeline = try VideoTranscodePipeline(
                    inVideoStream: inVideoStream,
                    outVideoStream: outVideoStream,
                    outCtx: outCtx,
                    outVideoIdx: outVideoIdx,
                    effectiveSAR: effectiveSAR,
                    writePacket: { packet in
                        try writePacketSafely(packet)
                        videoPacketsWritten += 1
                    }
                )
            }
        }

        // 2. Setup Audio Output Stream(s) (Track 1+)
        if let aInIdx = primaryAudioInIdx,
           let inAudioStream = inCtx.pointee.streams[aInIdx] {
            guard let outAudioStream = avformat_new_stream(outCtx, nil) else {
                throw RemuxError.createStreamFailed
            }
            outAudioIdx = nextOutIdx
            streamMapping[aInIdx] = outAudioIdx
            nextOutIdx += 1

            if !needsAudioTranscode {
                ret = avcodec_parameters_copy(outAudioStream.pointee.codecpar, inAudioStream.pointee.codecpar)
                guard ret >= 0 else { throw RemuxError.copyCodecParametersFailed(ret) }
                outAudioStream.pointee.time_base = inAudioStream.pointee.time_base
                outAudioStream.pointee.codecpar.pointee.codec_tag = 0

                let codecName = String(cString: avcodec_get_name(outAudioStream.pointee.codecpar.pointee.codec_id))
                AppLogger.info("Mapped input audio #\(aInIdx) -> output MP4 track #\(outAudioIdx) [AUDIO: \(codecName)]", tag: "Remuxer")
            } else {
                audioPipeline = try AudioTranscodePipeline(
                    inAudioStream: inAudioStream,
                    outAudioStream: outAudioStream,
                    outCtx: outCtx,
                    outAudioIdx: outAudioIdx,
                    writePacket: { packet in
                        try writePacketSafely(packet)
                        audioPacketsWritten += 1
                    }
                )
            }
        }

        // Open output file
        if (outCtx.pointee.oformat.pointee.flags & AVFMT_NOFILE) == 0 {
            ret = avio_open(&outCtx.pointee.pb, outputURL.path, AVIO_FLAG_WRITE)
            guard ret >= 0 else {
                throw RemuxError.openOutputFileFailed(ret)
            }
        }

        // Faststart movflags
        var muxerOpts: OpaquePointer? = nil
        av_dict_set(&muxerOpts, "movflags", "faststart", 0)
        defer {
            av_dict_free(&muxerOpts)
        }

        ret = avformat_write_header(outCtx, &muxerOpts)
        guard ret >= 0 else {
            throw RemuxError.writeHeaderFailed(ret)
        }

        guard let pkt = av_packet_alloc() else {
            throw RemuxError.createOutputContextFailed
        }
        defer {
            var mutablePkt: UnsafeMutablePointer<AVPacket>? = pkt
            av_packet_free(&mutablePkt)
        }

        let totalDurationSec = (inCtx.pointee.duration > 0)
            ? Double(inCtx.pointee.duration) / 1_000_000.0
            : 0.0

        // Packet processing loop
        while av_read_frame(inCtx, pkt) >= 0 {
            let inStreamIdx = Int(pkt.pointee.stream_index)
            if inStreamIdx == primaryVideoInIdx {
                if !needsVideoTranscode {
                    let outIdx = streamMapping[inStreamIdx]
                    if let inStream = inCtx.pointee.streams[inStreamIdx],
                       let outStream = outCtx.pointee.streams[Int(outIdx)] {
                        pkt.pointee.stream_index = outIdx
                        av_packet_rescale_ts(pkt, inStream.pointee.time_base, outStream.pointee.time_base)
                        pkt.pointee.pos = -1
                        try writePacketSafely(pkt)
                        videoPacketsWritten += 1

                        if totalDurationSec > 0 && videoPacketsWritten % 60 == 0 {
                            let pts = (pkt.pointee.pts != avNoPtsValue) ? pkt.pointee.pts : pkt.pointee.dts
                            if pts != avNoPtsValue {
                                let currentSec = Double(pts) * Double(inStream.pointee.time_base.num) / Double(inStream.pointee.time_base.den)
                                let p = min(max(currentSec / totalDurationSec, 0.0), 1.0)
                                reportProgress(p)
                            }
                        }
                    }
                } else if let vPipeline = videoPipeline, let inStream = inCtx.pointee.streams[inStreamIdx]?.pointee {
                    try vPipeline.process(packet: pkt) { rawPts in
                        if totalDurationSec > 0 && vPipeline.videoFrameCount % 30 == 0 {
                            let currentSec = Double(rawPts) * Double(inStream.time_base.num) / Double(inStream.time_base.den)
                            let p = min(max(currentSec / totalDurationSec, 0.0), 1.0)
                            reportProgress(p)
                        }
                    }
                }
            } else if inStreamIdx == primaryAudioInIdx {
                if !needsAudioTranscode {
                    let outIdx = streamMapping[inStreamIdx]
                    if let inStream = inCtx.pointee.streams[inStreamIdx],
                       let outStream = outCtx.pointee.streams[Int(outIdx)] {
                        pkt.pointee.stream_index = outIdx
                        av_packet_rescale_ts(pkt, inStream.pointee.time_base, outStream.pointee.time_base)
                        pkt.pointee.pos = -1
                        try writePacketSafely(pkt)
                        audioPacketsWritten += 1
                    }
                } else if let aPipeline = audioPipeline {
                    try aPipeline.process(packet: pkt)
                }
            }
            av_packet_unref(pkt)
        }

        // EOF Flushing for Video and Audio Transcoders
        try videoPipeline?.flush()
        try audioPipeline?.flush()

        av_write_trailer(outCtx)

        let methodLabel: String = {
            var parts: [String] = []
            if needsVideoTranscode { parts.append("video to H.264") }
            if needsAudioTranscode { parts.append("audio to AAC") }
            return parts.isEmpty ? "stream copy" : "transcoded " + parts.joined(separator: ", ")
        }()
        AppLogger.success("Processing complete (\(methodLabel)): wrote \(videoPacketsWritten) video packets, \(audioPacketsWritten) audio packets", tag: "Remuxer")

        if primaryVideoInIdx != nil && videoPacketsWritten == 0 {
            throw RemuxError.videoStreamMissingInOutput
        }
        if primaryAudioInIdx != nil && audioPacketsWritten == 0 {
            throw RemuxError.audioStreamMissingInOutput
        }
    }
}
