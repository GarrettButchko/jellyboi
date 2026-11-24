//
//  ApplePlayableContainer.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 11/13/26.
//

import Foundation

/// The single source of truth for which media containers AVPlayer can open on its own.
///
/// The device profile, offline playback, download remuxing, and the fallback stream resolver all
/// have to agree on this list — hard-coding it in each place is what let them drift apart.
nonisolated enum ApplePlayableContainer {

    /// Container extensions AVPlayer opens without server-side remuxing.
    static let names: [String] = ["mp4", "m4v", "mov"]

    /// Comma-separated form expected by Jellyfin's `DirectPlayProfile.container`.
    static let jellyfinContainerList = names.joined(separator: ",")

    /// Returns the first natively supported container found in `container`, if any.
    ///
    /// Handles single extensions ("mp4"), dot-prefixed (".mp4"), or comma-separated lists from Jellyfin/FFmpeg ("mov,mp4,m4a").
    static func preferredContainer(for container: String?) -> String? {
        guard let container else { return nil }
        let raw = container.lowercased()
        let items = raw.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "."))
        }
        for name in names {
            if items.contains(name) {
                return name
            }
        }
        return nil
    }

    /// True when `container` (for example `MediaSourceInfo.container`) is natively playable.
    ///
    /// Case-insensitive and tolerant of comma-separated format strings or missing container.
    static func supports(_ container: String?) -> Bool {
        preferredContainer(for: container) != nil
    }

    /// True when the file at `url` is in a natively playable container.
    static func canPlay(url: URL) -> Bool {
        supports(url.pathExtension)
    }
}
