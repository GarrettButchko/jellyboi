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
import Libswscale
import Libswresample

// MARK: - Local Media Remuxer & Hardware Transcoder

public enum RemuxError: LocalizedError {
    case openInputFailed(Int32)
    case findStreamInfoFailed(Int32)
    case createOutputContextFailed
    case createStreamFailed
    case copyCodecParametersFailed(Int32)
    case openOutputFileFailed(Int32)
    case writeHeaderFailed(Int32)
    case writeFrameFailed(Int32)
    case noCompatibleStreams
    case unsupportedVideoCodec(String)
    case unsupportedAudioCodec(String)
    case videoStreamMissingInOutput
    case audioStreamMissingInOutput
    case openDecoderFailed(Int32)
    case openEncoderFailed(Int32)
    case allocateFrameFailed

    public var errorDescription: String? {
        switch self {
        case .openInputFailed(let code): return "Failed to open input file (code \(code))"
        case .findStreamInfoFailed(let code): return "Failed to read stream info (code \(code))"
        case .createOutputContextFailed: return "Failed to create MP4 output context"
        case .createStreamFailed: return "Failed to create output stream"
        case .copyCodecParametersFailed(let code): return "Failed to copy codec parameters (code \(code))"
        case .openOutputFileFailed(let code): return "Failed to open output file for writing (code \(code))"
        case .writeHeaderFailed(let code): return "Failed to write MP4 header (code \(code))"
        case .writeFrameFailed(let code): return "Failed to write packet frame (code \(code))"
        case .noCompatibleStreams: return "No compatible audio or video streams found in source"
        case .unsupportedVideoCodec(let name): return "Video track uses codec '\(name)', which cannot be packaged into MP4 for offline playback."
        case .unsupportedAudioCodec(let name): return "Audio track uses codec '\(name)', which cannot be packaged into MP4 for offline playback."
        case .videoStreamMissingInOutput: return "Source file contained a video track, but no video packets could be written to the output MP4."
        case .audioStreamMissingInOutput: return "Source file contained an audio track, but no audio packets could be written to the output MP4."
        case .openDecoderFailed(let code): return "Failed to open decoder (code \(code))"
        case .openEncoderFailed(let code): return "Failed to open encoder (code \(code))"
        case .allocateFrameFailed: return "Failed to allocate frame memory"
        }
    }
}

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

    private static func isSupportedVideoCodec(_ codecID: AVCodecID) -> Bool {
        return codecID == AV_CODEC_ID_H264 ||
               codecID == AV_CODEC_ID_HEVC ||
               codecID == AV_CODEC_ID_MPEG4 ||
               codecID == AV_CODEC_ID_AV1 ||
               codecID == AV_CODEC_ID_PRORES
    }

    private static func isSupportedAudioCodec(_ codecID: AVCodecID) -> Bool {
        return codecID == AV_CODEC_ID_AAC ||
               codecID == AV_CODEC_ID_ALAC
    }

    private static func findCompatibleVideoEncoder() -> UnsafePointer<AVCodec>? {
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

    private static func resolveEffectiveSAR(
        inCtx: UnsafeMutablePointer<AVFormatContext>,
        inVideoStream: UnsafeMutablePointer<AVStream>,
        targetAspectRatio: String?
    ) -> AVRational {
        let cp = inVideoStream.pointee.codecpar.pointee
        let width = cp.width
        let height = cp.height
        let codedDAR = height > 0 ? (Double(width) / Double(height)) : 1.0

        // 1. Try parsing targetAspectRatio (e.g. from Jellyfin metadata "16:9", "1.78:1")
        if let targetAspect = targetAspectRatio?.trimmingCharacters(in: .whitespacesAndNewlines), !targetAspect.isEmpty {
            var targetDAR: Double? = nil
            if targetAspect.contains(":") {
                let parts = targetAspect.split(separator: ":")
                if parts.count == 2, let num = Double(parts[0]), let den = Double(parts[1]), den > 0 {
                    targetDAR = num / den
                }
            } else if targetAspect.contains("/") {
                let parts = targetAspect.split(separator: "/")
                if parts.count == 2, let num = Double(parts[0]), let den = Double(parts[1]), den > 0 {
                    targetDAR = num / den
                }
            } else if let val = Double(targetAspect), val > 0 {
                targetDAR = val
            }

            if let dar = targetDAR, width > 0, height > 0 {
                let diff = abs(dar - codedDAR) / codedDAR
                if diff > 0.01 {
                    var sarNum: Int32 = 0
                    var sarDen: Int32 = 0
                    let factor = 100_000.0
                    let num64 = Int64(round(dar * Double(height) * factor))
                    let den64 = Int64(round(Double(width) * factor))
                    av_reduce(&sarNum, &sarDen, num64, den64, 1024)
                    if sarNum > 0 && sarDen > 0 {
                        AppLogger.info("Calculated SAR \(sarNum):\(sarDen) from target aspect ratio '\(targetAspect)' (DAR: \(String(format: "%.3f", dar)), coded DAR: \(String(format: "%.3f", codedDAR)))", tag: "Remuxer")
                        return AVRational(num: sarNum, den: sarDen)
                    }
                }
            }
        }

        // 2. Try FFmpeg's container-level SAR detection (matroskadec DisplayWidth / DisplayHeight, etc.)
        let guessed = av_guess_sample_aspect_ratio(inCtx, inVideoStream, nil)
        if guessed.num > 0 && guessed.den > 0 && guessed.num != guessed.den {
            AppLogger.info("Detected container SAR \(guessed.num):\(guessed.den) via av_guess_sample_aspect_ratio", tag: "Remuxer")
            return guessed
        }

        // 3. Try stream-level SAR
        let stSAR = inVideoStream.pointee.sample_aspect_ratio
        if stSAR.num > 0 && stSAR.den > 0 && stSAR.num != stSAR.den {
            AppLogger.info("Using stream SAR \(stSAR.num):\(stSAR.den)", tag: "Remuxer")
            return stSAR
        }

        // 4. Try codecpar-level SAR
        let cpSAR = inVideoStream.pointee.codecpar.pointee.sample_aspect_ratio
        if cpSAR.num > 0 && cpSAR.den > 0 && cpSAR.num != cpSAR.den {
            AppLogger.info("Using codecpar SAR \(cpSAR.num):\(cpSAR.den)", tag: "Remuxer")
            return cpSAR
        }

        // 5. Default to square pixels or whatever stream has
        return (stSAR.num > 0 && stSAR.den > 0) ? stSAR : AVRational(num: 1, den: 1)
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

        // Determine if video needs transcoding:
        var needsVideoTranscode = false
        if let vIdx = primaryVideoInIdx,
           let cp = inCtx.pointee.streams[vIdx]?.pointee.codecpar?.pointee {
            needsVideoTranscode = !isSupportedVideoCodec(cp.codec_id)
            let codecName = String(cString: avcodec_get_name(cp.codec_id))
            if needsVideoTranscode {
                AppLogger.info("Video codec '\(codecName)' is not natively supported in MP4 for AVPlayer; hardware transcoding to H.264 enabled", tag: "Remuxer")
            } else {
                AppLogger.info("Video codec '\(codecName)' is natively supported; using fast stream copy", tag: "Remuxer")
            }
        }

        // Determine if audio needs transcoding:
        var needsAudioTranscode = false
        if let aIdx = primaryAudioInIdx,
           let cp = inCtx.pointee.streams[aIdx]?.pointee.codecpar?.pointee {
            needsAudioTranscode = !isSupportedAudioCodec(cp.codec_id)
            let codecName = String(cString: avcodec_get_name(cp.codec_id))
            if needsAudioTranscode {
                AppLogger.info("Audio codec '\(codecName)' is not natively supported in MP4 for AVPlayer; transcoding to AAC enabled", tag: "Remuxer")
            } else {
                AppLogger.info("Audio codec '\(codecName)' is natively supported; using fast stream copy", tag: "Remuxer")
            }
        }

        // Video transcoding state variables
        var decCtx: UnsafeMutablePointer<AVCodecContext>? = nil
        var encCtx: UnsafeMutablePointer<AVCodecContext>? = nil
        var swsCtx: UnsafeMutablePointer<SwsContext>? = nil
        var decodedFrame: UnsafeMutablePointer<AVFrame>? = nil
        var scaledFrame: UnsafeMutablePointer<AVFrame>? = nil
        var encPkt: UnsafeMutablePointer<AVPacket>? = nil

        // Audio transcoding state variables
        var aDecCtx: UnsafeMutablePointer<AVCodecContext>? = nil
        var aEncCtx: UnsafeMutablePointer<AVCodecContext>? = nil
        var aSwrCtx: OpaquePointer? = nil
        var aFifo: OpaquePointer? = nil
        var decodedAudioFrame: UnsafeMutablePointer<AVFrame>? = nil
        var resampledAudioFrame: UnsafeMutablePointer<AVFrame>? = nil
        var outAudioFrame: UnsafeMutablePointer<AVFrame>? = nil
        var encAudioPkt: UnsafeMutablePointer<AVPacket>? = nil
        var nextAudioPts: Int64 = 0
        var aFrameSize: Int = 1024

        defer {
            avcodec_free_context(&decCtx)
            avcodec_free_context(&encCtx)
            if let swsCtx { sws_freeContext(swsCtx) }
            av_frame_free(&decodedFrame)
            av_frame_free(&scaledFrame)
            av_packet_free(&encPkt)

            avcodec_free_context(&aDecCtx)
            avcodec_free_context(&aEncCtx)
            swr_free(&aSwrCtx)
            if let fifo = aFifo { av_audio_fifo_free(fifo) }
            av_frame_free(&decodedAudioFrame)
            av_frame_free(&resampledAudioFrame)
            av_frame_free(&outAudioFrame)
            av_packet_free(&encAudioPkt)
        }

        var streamMapping = [Int32](repeating: -1, count: nbStreams)
        var nextOutIdx: Int32 = 0
        var outVideoIdx: Int32 = -1
        var outAudioIdx: Int32 = -1

        // 1. Setup Video Output Stream (Track 0)
        if let vInIdx = primaryVideoInIdx,
           let inVideoStream = inCtx.pointee.streams[vInIdx] {
            guard let outVideoStream = avformat_new_stream(outCtx, nil) else {
                throw RemuxError.createStreamFailed
            }
            outVideoIdx = nextOutIdx
            streamMapping[vInIdx] = outVideoIdx
            nextOutIdx += 1

            if !needsVideoTranscode {
                // Direct stream copy
                ret = avcodec_parameters_copy(outVideoStream.pointee.codecpar, inVideoStream.pointee.codecpar)
                guard ret >= 0 else { throw RemuxError.copyCodecParametersFailed(ret) }
                outVideoStream.pointee.time_base = inVideoStream.pointee.time_base
                outVideoStream.pointee.r_frame_rate = inVideoStream.pointee.r_frame_rate
                outVideoStream.pointee.avg_frame_rate = inVideoStream.pointee.avg_frame_rate

                let effectiveSAR = resolveEffectiveSAR(
                    inCtx: inCtx,
                    inVideoStream: inVideoStream,
                    targetAspectRatio: targetAspectRatio
                )
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
                // Initialize video decoder
                let inCodecPar = inVideoStream.pointee.codecpar.pointee
                guard let decoder = avcodec_find_decoder(inCodecPar.codec_id) else {
                    let codecName = String(cString: avcodec_get_name(inCodecPar.codec_id))
                    throw RemuxError.unsupportedVideoCodec("No decoder available for \(codecName)")
                }
                guard let dCtx = avcodec_alloc_context3(decoder) else {
                    throw RemuxError.createOutputContextFailed
                }
                decCtx = dCtx
                ret = avcodec_parameters_to_context(dCtx, inVideoStream.pointee.codecpar)
                guard ret >= 0 else { throw RemuxError.copyCodecParametersFailed(ret) }
                ret = avcodec_open2(dCtx, decoder, nil)
                guard ret >= 0 else { throw RemuxError.openDecoderFailed(ret) }

                // Initialize video encoder
                guard let encoder = findCompatibleVideoEncoder() else {
                    throw RemuxError.unsupportedVideoCodec("No suitable video encoder found on device")
                }
                guard let eCtx = avcodec_alloc_context3(encoder) else {
                    throw RemuxError.createOutputContextFailed
                }
                encCtx = eCtx

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

                let effectiveSAR = resolveEffectiveSAR(
                    inCtx: inCtx,
                    inVideoStream: inVideoStream,
                    targetAspectRatio: targetAspectRatio
                )
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

                // Check if swscale is needed
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
                        swsCtx = UnsafeMutablePointer<SwsContext>(rawSws)
                    }
                    scaledFrame = av_frame_alloc()
                    guard let sf = scaledFrame else { throw RemuxError.allocateFrameFailed }
                    sf.pointee.format = eCtx.pointee.pix_fmt.rawValue
                    sf.pointee.width = eCtx.pointee.width
                    sf.pointee.height = eCtx.pointee.height
                    let bufRet = av_frame_get_buffer(sf, 32)
                    guard bufRet >= 0 else { throw RemuxError.allocateFrameFailed }
                }

                decodedFrame = av_frame_alloc()
                encPkt = av_packet_alloc()
                guard decodedFrame != nil, encPkt != nil else {
                    throw RemuxError.allocateFrameFailed
                }

                AppLogger.info("Mapped input video #\(vInIdx) -> output MP4 track #\(outVideoIdx) [Transcoding \(inCodecPar.width)x\(inCodecPar.height) to \(String(cString: encoder.pointee.name))]", tag: "Remuxer")
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
                let inCodecPar = inAudioStream.pointee.codecpar.pointee
                guard let aDecoder = avcodec_find_decoder(inCodecPar.codec_id) else {
                    let codecName = String(cString: avcodec_get_name(inCodecPar.codec_id))
                    throw RemuxError.unsupportedAudioCodec("No decoder available for \(codecName)")
                }
                guard let adCtx = avcodec_alloc_context3(aDecoder) else {
                    throw RemuxError.createOutputContextFailed
                }
                aDecCtx = adCtx
                ret = avcodec_parameters_to_context(adCtx, inAudioStream.pointee.codecpar)
                guard ret >= 0 else { throw RemuxError.copyCodecParametersFailed(ret) }
                ret = avcodec_open2(adCtx, aDecoder, nil)
                guard ret >= 0 else { throw RemuxError.openDecoderFailed(ret) }

                guard let aEncoder = avcodec_find_encoder(AV_CODEC_ID_AAC) else {
                    throw RemuxError.unsupportedAudioCodec("AAC audio encoder not available")
                }
                guard let aeCtx = avcodec_alloc_context3(aEncoder) else {
                    throw RemuxError.createOutputContextFailed
                }
                aEncCtx = aeCtx

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
                aSwrCtx = validSwr

                aFrameSize = aeCtx.pointee.frame_size > 0 ? Int(aeCtx.pointee.frame_size) : 1024
                guard let fifo = av_audio_fifo_alloc(aeCtx.pointee.sample_fmt, 2, Int32(aFrameSize * 4)) else {
                    throw RemuxError.allocateFrameFailed
                }
                aFifo = fifo

                decodedAudioFrame = av_frame_alloc()
                resampledAudioFrame = av_frame_alloc()
                outAudioFrame = av_frame_alloc()
                encAudioPkt = av_packet_alloc()

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

                AppLogger.info("Mapped input audio #\(aInIdx) -> output MP4 track #\(outAudioIdx) [Transcoding \(inCodecPar.sample_rate)Hz to AAC stereo 192k]", tag: "Remuxer")
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

        var videoPacketsWritten = 0
        var audioPacketsWritten = 0
        var videoFrameCount: Int64 = 0
        var lastVideoPts: Int64 = -1

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
                        let writeRet = av_interleaved_write_frame(outCtx, pkt)
                        if writeRet < 0 {
                            av_packet_unref(pkt)
                            throw RemuxError.writeFrameFailed(writeRet)
                        }
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
                } else if let dCtx = decCtx, let eCtx = encCtx, let dFrame = decodedFrame, let ePkt = encPkt {
                    let inVideoStream = inCtx.pointee.streams[inStreamIdx]!.pointee
                    let outVideoStream = outCtx.pointee.streams[Int(outVideoIdx)]!.pointee

                    ret = avcodec_send_packet(dCtx, pkt)
                    if ret >= 0 {
                        while avcodec_receive_frame(dCtx, dFrame) >= 0 {
                            let frameToEncode: UnsafeMutablePointer<AVFrame>
                            let rawPts = (dFrame.pointee.pts != avNoPtsValue) ? dFrame.pointee.pts : dFrame.pointee.best_effort_timestamp
                            let computedPts: Int64 = (rawPts != avNoPtsValue)
                                ? av_rescale_q(rawPts, inVideoStream.time_base, eCtx.pointee.time_base)
                                : (lastVideoPts + 1)
                            let safePts = max(computedPts, lastVideoPts + 1)
                            lastVideoPts = safePts

                            if let sws = swsCtx, let sf = scaledFrame {
                                _ = av_frame_make_writable(sf)
                                _ = sws_scale_frame(sws, sf, dFrame)
                                sf.pointee.pts = safePts
                                sf.pointee.duration = av_rescale_q(dFrame.pointee.duration, inVideoStream.time_base, eCtx.pointee.time_base)
                                frameToEncode = sf
                            } else {
                                dFrame.pointee.pts = safePts
                                frameToEncode = dFrame
                            }

                            ret = avcodec_send_frame(eCtx, frameToEncode)
                            if ret >= 0 {
                                while avcodec_receive_packet(eCtx, ePkt) >= 0 {
                                    av_packet_rescale_ts(ePkt, eCtx.pointee.time_base, outVideoStream.time_base)
                                    ePkt.pointee.stream_index = outVideoIdx
                                    ePkt.pointee.pos = -1
                                    let writeRet = av_interleaved_write_frame(outCtx, ePkt)
                                    av_packet_unref(ePkt)
                                    if writeRet < 0 {
                                        throw RemuxError.writeFrameFailed(writeRet)
                                    }
                                    videoPacketsWritten += 1
                                }
                            }
                            videoFrameCount += 1
                            av_frame_unref(dFrame)

                            if totalDurationSec > 0 && videoFrameCount % 30 == 0 {
                                let currentSec = Double(rawPts) * Double(inVideoStream.time_base.num) / Double(inVideoStream.time_base.den)
                                let p = min(max(currentSec / totalDurationSec, 0.0), 1.0)
                                reportProgress(p)
                            }
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
                        let writeRet = av_interleaved_write_frame(outCtx, pkt)
                        if writeRet < 0 {
                            av_packet_unref(pkt)
                            throw RemuxError.writeFrameFailed(writeRet)
                        }
                        audioPacketsWritten += 1
                    }
                } else if let adCtx = aDecCtx,
                           let aeCtx = aEncCtx,
                           let swr = aSwrCtx,
                           let fifo = aFifo,
                           let dAudioFrame = decodedAudioFrame,
                           let rAudioFrame = resampledAudioFrame,
                           let oaf = outAudioFrame,
                           let ePkt = encAudioPkt,
                           let outAudioStream = outCtx.pointee.streams[Int(outAudioIdx)]?.pointee {
                    ret = avcodec_send_packet(adCtx, pkt)
                    if ret >= 0 {
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
                                _ = writeFrameToAudioFifo(fifo: fifo, frame: rAudioFrame)
                            }
                            av_frame_unref(dAudioFrame)

                            // Read completed aFrameSize chunks from FIFO and encode
                            while av_audio_fifo_size(fifo) >= Int32(aFrameSize) {
                                _ = av_frame_make_writable(oaf)
                                _ = readFrameFromAudioFifo(fifo: fifo, frame: oaf, nbSamples: Int32(aFrameSize))
                                oaf.pointee.nb_samples = Int32(aFrameSize)
                                oaf.pointee.pts = nextAudioPts
                                nextAudioPts += Int64(aFrameSize)

                                ret = avcodec_send_frame(aeCtx, oaf)
                                if ret >= 0 {
                                    while avcodec_receive_packet(aeCtx, ePkt) >= 0 {
                                        av_packet_rescale_ts(ePkt, aeCtx.pointee.time_base, outAudioStream.time_base)
                                        ePkt.pointee.stream_index = outAudioIdx
                                        ePkt.pointee.pos = -1
                                        let writeRet = av_interleaved_write_frame(outCtx, ePkt)
                                        av_packet_unref(ePkt)
                                        if writeRet < 0 {
                                            throw RemuxError.writeFrameFailed(writeRet)
                                        }
                                        audioPacketsWritten += 1
                                    }
                                }
                            }
                        }
                    }
                }
            }
            av_packet_unref(pkt)
        }

        // EOF Flushing for Video Transcoder
        if needsVideoTranscode, let dCtx = decCtx, let eCtx = encCtx, let dFrame = decodedFrame, let ePkt = encPkt {
            let inVideoStream = inCtx.pointee.streams[primaryVideoInIdx!]!.pointee
            let outVideoStream = outCtx.pointee.streams[Int(outVideoIdx)]!.pointee

            // 1. Drain decoder
            ret = avcodec_send_packet(dCtx, nil)
            if ret >= 0 {
                while avcodec_receive_frame(dCtx, dFrame) >= 0 {
                    let frameToEncode: UnsafeMutablePointer<AVFrame>
                    let rawPts = (dFrame.pointee.pts != avNoPtsValue) ? dFrame.pointee.pts : dFrame.pointee.best_effort_timestamp
                    let computedPts: Int64 = (rawPts != avNoPtsValue)
                        ? av_rescale_q(rawPts, inVideoStream.time_base, eCtx.pointee.time_base)
                        : (lastVideoPts + 1)
                    let safePts = max(computedPts, lastVideoPts + 1)
                    lastVideoPts = safePts

                    if let sws = swsCtx, let sf = scaledFrame {
                        _ = av_frame_make_writable(sf)
                        _ = sws_scale_frame(sws, sf, dFrame)
                        sf.pointee.pts = safePts
                        frameToEncode = sf
                    } else {
                        dFrame.pointee.pts = safePts
                        frameToEncode = dFrame
                    }

                    ret = avcodec_send_frame(eCtx, frameToEncode)
                    if ret >= 0 {
                        while avcodec_receive_packet(eCtx, ePkt) >= 0 {
                            av_packet_rescale_ts(ePkt, eCtx.pointee.time_base, outVideoStream.time_base)
                            ePkt.pointee.stream_index = outVideoIdx
                            ePkt.pointee.pos = -1
                            let writeRet = av_interleaved_write_frame(outCtx, ePkt)
                            av_packet_unref(ePkt)
                            if writeRet < 0 {
                                throw RemuxError.writeFrameFailed(writeRet)
                            }
                            videoPacketsWritten += 1
                        }
                    }
                    videoFrameCount += 1
                    av_frame_unref(dFrame)
                }
            }

            // 2. Drain encoder
            ret = avcodec_send_frame(eCtx, nil)
            if ret >= 0 {
                while avcodec_receive_packet(eCtx, ePkt) >= 0 {
                    av_packet_rescale_ts(ePkt, eCtx.pointee.time_base, outVideoStream.time_base)
                    ePkt.pointee.stream_index = outVideoIdx
                    ePkt.pointee.pos = -1
                    let writeRet = av_interleaved_write_frame(outCtx, ePkt)
                    av_packet_unref(ePkt)
                    if writeRet < 0 {
                        throw RemuxError.writeFrameFailed(writeRet)
                    }
                    videoPacketsWritten += 1
                }
            }
        }

        // EOF Flushing for Audio Transcoder
        if needsAudioTranscode,
           let adCtx = aDecCtx,
           let aeCtx = aEncCtx,
           let swr = aSwrCtx,
           let fifo = aFifo,
           let dAudioFrame = decodedAudioFrame,
           let rAudioFrame = resampledAudioFrame,
           let oaf = outAudioFrame,
           let ePkt = encAudioPkt,
           let outAudioStream = outCtx.pointee.streams[Int(outAudioIdx)]?.pointee {
            // 1. Drain decoder
            ret = avcodec_send_packet(adCtx, nil)
            if ret >= 0 {
                while avcodec_receive_frame(adCtx, dAudioFrame) >= 0 {
                    av_frame_unref(rAudioFrame)
                    rAudioFrame.pointee.format = aeCtx.pointee.sample_fmt.rawValue
                    rAudioFrame.pointee.sample_rate = aeCtx.pointee.sample_rate
                    _ = av_channel_layout_copy(&rAudioFrame.pointee.ch_layout, &aeCtx.pointee.ch_layout)

                    let convRet = swr_convert_frame(swr, rAudioFrame, dAudioFrame)
                    if convRet >= 0 && rAudioFrame.pointee.nb_samples > 0 {
                        _ = writeFrameToAudioFifo(fifo: fifo, frame: rAudioFrame)
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
                _ = writeFrameToAudioFifo(fifo: fifo, frame: rAudioFrame)
            }
            av_frame_unref(rAudioFrame)

            // 3. Drain FIFO
            while av_audio_fifo_size(fifo) > 0 {
                let pendingSamples = min(av_audio_fifo_size(fifo), Int32(aFrameSize))
                _ = av_frame_make_writable(oaf)
                _ = readFrameFromAudioFifo(fifo: fifo, frame: oaf, nbSamples: pendingSamples)
                if pendingSamples < Int32(aFrameSize) {
                    padAudioFrameWithSilence(frame: oaf, offset: pendingSamples, nbSamples: Int32(aFrameSize) - pendingSamples)
                }
                oaf.pointee.nb_samples = Int32(aFrameSize)
                oaf.pointee.pts = nextAudioPts
                nextAudioPts += Int64(aFrameSize)

                ret = avcodec_send_frame(aeCtx, oaf)
                if ret >= 0 {
                    while avcodec_receive_packet(aeCtx, ePkt) >= 0 {
                        av_packet_rescale_ts(ePkt, aeCtx.pointee.time_base, outAudioStream.time_base)
                        ePkt.pointee.stream_index = outAudioIdx
                        ePkt.pointee.pos = -1
                        let writeRet = av_interleaved_write_frame(outCtx, ePkt)
                        av_packet_unref(ePkt)
                        if writeRet < 0 {
                            throw RemuxError.writeFrameFailed(writeRet)
                        }
                        audioPacketsWritten += 1
                    }
                }
            }

            // 4. Drain audio encoder
            ret = avcodec_send_frame(aeCtx, nil)
            if ret >= 0 {
                while avcodec_receive_packet(aeCtx, ePkt) >= 0 {
                    av_packet_rescale_ts(ePkt, aeCtx.pointee.time_base, outAudioStream.time_base)
                    ePkt.pointee.stream_index = outAudioIdx
                    ePkt.pointee.pos = -1
                    let writeRet = av_interleaved_write_frame(outCtx, ePkt)
                    av_packet_unref(ePkt)
                    if writeRet < 0 {
                        throw RemuxError.writeFrameFailed(writeRet)
                    }
                    audioPacketsWritten += 1
                }
            }
        }

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
