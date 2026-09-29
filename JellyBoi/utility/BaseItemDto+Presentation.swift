//
//  BaseItemDto+Presentation.swift
//  JellyBoi
//
//

import Foundation
import CoreGraphics
import JellyfinAPI

extension BaseItemDto {

    /// Standard aspect ratio (width / height) for poster/thumbnail cards.
    /// Uses `primaryImageAspectRatio` if positive, else defaults to 16:9 for episodes and 2:3 for others.
    var imageAspectRatio: CGFloat {
        if let ratio = primaryImageAspectRatio, ratio > 0 {
            return CGFloat(ratio)
        }
        return type == .episode ? (16.0 / 9.0) : (2.0 / 3.0)
    }

    /// Formatted runtime string (e.g. "2h 15m" or "45m") from `runTimeTicks`.
    var formattedRuntime: String? {
        guard let ticks = runTimeTicks, ticks > 0 else { return nil }
        let totalSeconds = Int(ticks / 10_000_000)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        guard hours > 0 || minutes > 0 else { return nil }
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }

    /// Resets playback progress and watch state to unplayed.
    mutating func clearProgress() {
        userData?.playedPercentage = 0
        userData?.isPlayed = false
        userData?.playbackPositionTicks = 0
    }
}

extension Array where Element == BaseItemDto {
    /// Clears progress for all items matching the given ID, optionally matching series ID as well.
    mutating func clearProgress(for itemID: String, matchingSeries: Bool = false) {
        for index in indices {
            if self[index].id == itemID || (matchingSeries && self[index].seriesID == itemID) {
                self[index].clearProgress()
            }
        }
    }
}
