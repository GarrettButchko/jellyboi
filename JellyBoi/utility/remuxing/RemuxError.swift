//
//  RemuxError.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 10/14/26.
//

import Foundation

// MARK: - Remux Error

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
        case .openInputFailed(let code):
            return "Failed to open input file (code \(code))"
        case .findStreamInfoFailed(let code):
            return "Failed to read stream info (code \(code))"
        case .createOutputContextFailed:
            return "Failed to create MP4 output context"
        case .createStreamFailed:
            return "Failed to create output stream"
        case .copyCodecParametersFailed(let code):
            return "Failed to copy codec parameters (code \(code))"
        case .openOutputFileFailed(let code):
            return "Failed to open output file for writing (code \(code))"
        case .writeHeaderFailed(let code):
            return "Failed to write MP4 header (code \(code))"
        case .writeFrameFailed(let code):
            return "Failed to write packet frame (code \(code))"
        case .noCompatibleStreams:
            return "No compatible audio or video streams found in source"
        case .unsupportedVideoCodec(let name):
            return "Video track uses codec '\(name)', which cannot be packaged into MP4 for offline playback."
        case .unsupportedAudioCodec(let name):
            return "Audio track uses codec '\(name)', which cannot be packaged into MP4 for offline playback."
        case .videoStreamMissingInOutput:
            return "Source file contained a video track, but no video packets could be written to the output MP4."
        case .audioStreamMissingInOutput:
            return "Source file contained an audio track, but no audio packets could be written to the output MP4."
        case .openDecoderFailed(let code):
            return "Failed to open decoder (code \(code))"
        case .openEncoderFailed(let code):
            return "Failed to open encoder (code \(code))"
        case .allocateFrameFailed:
            return "Failed to allocate frame memory"
        }
    }
}
