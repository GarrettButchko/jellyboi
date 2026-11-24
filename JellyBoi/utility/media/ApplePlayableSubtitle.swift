//
//  ApplePlayableSubtitle.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 11/23/26.
//

import Foundation
import JellyfinAPI

/// Defines subtitle codecs and formats that AVPlayer natively supports or that
/// Jellyfin can package into HLS / sidecar delivery without re-encoding video.
nonisolated enum ApplePlayableSubtitle {

    /// Subtitle codecs that AVPlayer natively supports (or Jellyfin can deliver via HLS text streams).
    static let compatibleCodecs: Set<String> = [
        "vtt",
        "webvtt",
        "subrip",
        "srt",
        "mov_text",
        "tx3g",
        "ttml",
        "imsc1",
        "cea-608",
        "cea-708"
    ]

    /// Returns true if the subtitle codec is natively supported by AVPlayer or can be delivered via HLS.
    static func isCompatible(codec: String?) -> Bool {
        guard let codec = codec?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            return false
        }
        return compatibleCodecs.contains(codec)
    }

    /// Returns true if the media stream is a subtitle stream compatible with AVPlayer.
    static func isCompatible(_ stream: MediaStream?) -> Bool {
        guard let stream, stream.type == .subtitle else { return false }
        return isCompatible(codec: stream.codec)
    }
}
