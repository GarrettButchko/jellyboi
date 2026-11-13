//
//  ApplePlayableContainer.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 11/13/26.
//

import Foundation

// MARK: - Apple Playable Containers

/// The single source of truth for which media containers AVPlayer can open on its own.
///
/// This list drives four separate decisions that must always agree:
/// - the direct-play profile advertised to the server (`PlayerViewModel.appleDeviceProfile`),
/// - whether a downloaded file is worth playing offline (`DownloadStorage`),
/// - whether a download can be kept as-is or must be remuxed to MP4 (`DownloadManager`,
///   `DownloadPostProcessor`),
/// - and whether the fallback stream resolver may request a direct static stream instead of HLS.
///
/// Hard-coding the list in each place is what let them drift apart, so every one of them reads it
/// from here.
nonisolated enum ApplePlayableContainer {

    /// Container extensions AVPlayer opens without server-side remuxing.
    static let names: [String] = ["mp4", "m4v", "mov"]

    /// Comma-separated form expected by Jellyfin's `DirectPlayProfile.container`.
    static var jellyfinContainerList: String {
        names.joined(separator: ",")
    }

    /// True when `container` (for example `MediaSourceInfo.container`) is natively playable.
    ///
    /// Case-insensitive and tolerant of a missing container, so callers do not have to normalise first.
    static func contains(_ container: String?) -> Bool {
        guard let container else { return false }
        return names.contains(container.lowercased())
    }

    /// True when the file at `url` is in a natively playable container.
    static func canPlay(url: URL) -> Bool {
        contains(url.pathExtension)
    }
}
