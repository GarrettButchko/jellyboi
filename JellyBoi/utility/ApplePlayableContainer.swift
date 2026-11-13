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

    /// True when `container` (for example `MediaSourceInfo.container`) is natively playable.
    ///
    /// Case-insensitive and tolerant of a missing container, so callers do not have to normalise first.
    static func supports(_ container: String?) -> Bool {
        guard let container else { return false }
        return names.contains(container.lowercased())
    }

    /// True when the file at `url` is in a natively playable container.
    static func canPlay(url: URL) -> Bool {
        supports(url.pathExtension)
    }
}
