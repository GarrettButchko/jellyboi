//
//  BaseItemDto+Presentation.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 8/25/26.
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

    /// Updates playback progress and watch state for the item.
    mutating func updateProgress(positionTicks: Int, totalTicks: Int?) {
        let total = totalTicks ?? runTimeTicks.map { Int($0) } ?? 0
        let percentage = total > 0 ? (Double(positionTicks) / Double(total)) * 100.0 : 0.0
        let isPlayed = percentage >= 85.0
        if userData == nil {
            userData = UserItemDataDto(
                isPlayed: isPlayed,
                itemID: id,
                key: id ?? UUID().uuidString,
                playbackPositionTicks: positionTicks,
                playedPercentage: percentage
            )
        } else {
            userData?.playbackPositionTicks = positionTicks
            userData?.playedPercentage = percentage
            userData?.isPlayed = isPlayed
        }
    }

    /// Indicates whether the item is marked as a favorite.
    var isFavorite: Bool {
        get { userData?.isFavorite == true }
        set {
            if userData != nil {
                userData?.isFavorite = newValue
            } else {
                userData = UserItemDataDto(isFavorite: newValue, key: id ?? "")
            }
        }
    }

    /// Updates the favorite status on the item's `userData`.
    mutating func setFavorite(_ isFavorite: Bool) {
        self.isFavorite = isFavorite
    }

    // MARK: - Playback State & Progress Helpers

    /// Watch progress ratio from 0.0 to 1.0. Returns nil if unplayed or no progress recorded.
    var watchProgress: Double? {
        if userData?.isPlayed == true { return 1.0 }
        guard let percent = userData?.playedPercentage else { return nil }
        return min(max(percent / 100.0, 0), 1.0)
    }

    /// Whether the item has been watched (completed >= 85% or marked played).
    var isWatched: Bool {
        if userData?.isPlayed == true { return true }
        return (watchProgress ?? 0) >= 0.85
    }

    /// Whether the item has positive playback progress (ticks or percent >= 1%).
    var hasProgress: Bool {
        if let percent = userData?.playedPercentage, percent >= 1.0 { return true }
        if let ticks = userData?.playbackPositionTicks, ticks > 0 {
            let total = runTimeTicks.map { Int($0) } ?? 0
            if total > 0 {
                return (Double(ticks) / Double(total)) * 100.0 >= 1.0
            }
            return true
        }
        return false
    }

    /// Whether the item is partially watched and not completed.
    var isInProgress: Bool {
        if isWatched { return false }
        return hasProgress && progressPercentage > 0
    }

    /// Whether a progress indicator (ring or bar) should be visible (suppressed at 0%).
    var isProgressVisible: Bool {
        if isWatched { return true }
        guard isInProgress else { return false }
        return progressPercentage > 0
    }

    /// Progress percentage integer between 0 and 100.
    var progressPercentage: Int {
        if isWatched { return 100 }
        guard let wp = watchProgress else { return 0 }
        return Int(wp * 100)
    }

    /// Formatted progress percentage string (e.g. "45%").
    var percentText: String {
        "\(progressPercentage)%"
    }

    /// Formatted remaining runtime string (e.g. "1h 12m left").
    var timeRemainingFormatted: String? {
        guard let ticks = runTimeTicks, ticks > 0,
              let percent = userData?.playedPercentage, percent >= 1.0, percent < 85.0 else { return nil }
        let totalSeconds = Int(ticks / 10_000_000)
        let remainingSeconds = totalSeconds - Int(Double(totalSeconds) * percent / 100.0)
        guard remainingSeconds > 60 else { return nil }
        let hours = remainingSeconds / 3600
        let minutes = (remainingSeconds % 3600) / 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
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

    /// Updates progress for all items matching the given ID.
    mutating func updateProgress(for itemID: String, positionTicks: Int, totalTicks: Int?) {
        for index in indices {
            if self[index].id == itemID {
                self[index].updateProgress(positionTicks: positionTicks, totalTicks: totalTicks)
            }
        }
    }

    /// Updates the favorite state for all items matching the given ID.
    mutating func updateFavorite(for itemID: String, isFavorite: Bool) {
        for index in indices {
            if self[index].id == itemID {
                self[index].setFavorite(isFavorite)
            }
        }
    }
}
