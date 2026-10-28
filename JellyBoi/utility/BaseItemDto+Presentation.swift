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
    /// Uses `primaryImageAspectRatio` if positive, else defaults to 16:9 for episodes/videos/trailers and 2:3 for others.
    var imageAspectRatio: CGFloat {
        if let ratio = primaryImageAspectRatio, ratio > 0 {
            return CGFloat(ratio)
        }
        return (type == .episode || type == .video || type == .trailer) ? (16.0 / 9.0) : (2.0 / 3.0)
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
        if type == .series, let unplayed = userData?.unplayedItemCount, unplayed == 0 { return true }
        return (watchProgress ?? 0) >= 0.85
    }

    /// Playback position in ticks for resuming playback.
    /// Prefers `playbackPositionTicks` if positive; otherwise computes from `playedPercentage` and `runTimeTicks`.
    var resumePlaybackTicks: Int {
        if let ticks = userData?.playbackPositionTicks, ticks > 0 {
            return ticks
        }
        if let percent = userData?.playedPercentage, percent > 0 {
            let total = runTimeTicks.map { Int($0) } ?? 0
            if total > 0 {
                return Int((Double(total) * percent) / 100.0)
            }
        }
        return 0
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

    // MARK: - Cumulative & Series Progress Helpers

    /// Computes cumulative watched progress (from 0.0 to 1.0) across an array of media items.
    /// Each completed item contributes 1.0, while in-progress items contribute their individual watchProgress.
    public static func cumulativeProgress(for items: [BaseItemDto], allEpisodes: [BaseItemDto] = []) -> Double {
        guard !items.isEmpty else { return 0.0 }
        let total = Double(items.count)
        let sum = items.reduce(0.0) { runningSum, item in
            if item.isWatched {
                return runningSum + 1.0
            }
            if item.type == .series, let seriesID = item.id {
                let seriesEpisodes = allEpisodes.filter { $0.seriesID == seriesID }
                if !seriesEpisodes.isEmpty {
                    return runningSum + cumulativeProgress(for: seriesEpisodes, allEpisodes: allEpisodes)
                }
            }
            return runningSum + (item.watchProgress ?? 0.0)
        }
        return sum / total
    }

    /// Evaluates whether a series is watched based on its episode data and user data.
    public func isSeriesWatched(allEpisodes: [BaseItemDto] = []) -> Bool {
        guard type == .series else { return isWatched }
        if let unplayed = userData?.unplayedItemCount, unplayed == 0 { return true }
        if userData?.isPlayed == true { return true }
        let showEpisodes = allEpisodes.filter { $0.seriesID == id }
        if !showEpisodes.isEmpty {
            return showEpisodes.allSatisfy { $0.isWatched }
        }
        return false
    }

    /// Computes the series watch progress (0.0 to 1.0) matching the MediaDetailView progress ring.
    public func seriesWatchProgress(allEpisodes: [BaseItemDto] = []) -> Double? {
        guard type == .series else { return watchProgress }
        if isSeriesWatched(allEpisodes: allEpisodes) { return 1.0 }
        let showEpisodes = allEpisodes.filter { $0.seriesID == id }
        if !showEpisodes.isEmpty {
            return BaseItemDto.cumulativeProgress(for: showEpisodes, allEpisodes: allEpisodes)
        }
        if let unplayed = userData?.unplayedItemCount,
           let total = recursiveItemCount ?? episodeCount, total > 0 {
            return max(0.0, min(1.0, Double(total - unplayed) / Double(total)))
        }
        return watchProgress
    }

    /// Evaluates whether a series is currently in-progress.
    public func isSeriesInProgress(allEpisodes: [BaseItemDto] = [], resumeShows: [BaseItemDto] = []) -> Bool {
        guard type == .series else { return isInProgress }
        if isSeriesWatched(allEpisodes: allEpisodes) { return false }
        let showEpisodes = allEpisodes.filter { $0.seriesID == id }
        if !showEpisodes.isEmpty {
            return showEpisodes.contains { $0.isWatched || $0.isInProgress }
        }
        if resumeShows.contains(where: { $0.seriesID == id || $0.id == id }) {
            return true
        }
        if let progress = seriesWatchProgress(allEpisodes: allEpisodes), progress > 0 {
            return true
        }
        return isInProgress
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

    /// Determines the next playable item in an ordered sequence of media items (e.g. episodes or collection items).
    /// - If `fromBeginning` is true, returns the first item.
    /// - If any items were completed, returns the first in-progress or unplayed item after the latest completed item.
    /// - If no item was completed yet, returns the first in-progress item, or the first item if none started.
    /// - If all items are completed, restarts from the first item.
    func nextPlayableItem(fromBeginning: Bool = false) -> BaseItemDto? {
        guard !isEmpty else { return nil }
        if fromBeginning {
            return first
        }

        func isCompleted(_ item: BaseItemDto) -> Bool {
            if item.userData?.isPlayed == true { return true }
            if item.type == .series, let unplayed = item.userData?.unplayedItemCount, unplayed == 0 { return true }
            if let percent = item.userData?.playedPercentage, percent >= 85.0 { return true }
            return false
        }

        func isInProgress(_ item: BaseItemDto) -> Bool {
            guard !isCompleted(item) else { return false }
            if let percent = item.userData?.playedPercentage, percent > 0 { return true }
            if let ticks = item.userData?.playbackPositionTicks, ticks > 0 { return true }
            return false
        }

        let lastCompletedIndex = lastIndex(where: { isCompleted($0) })

        if let lastCompletedIndex {
            let remaining = self[(lastCompletedIndex + 1)...]
            if !remaining.isEmpty {
                if let inProgressItem = remaining.first(where: { isInProgress($0) }) {
                    return inProgressItem
                }
                return remaining.first
            } else {
                // All items completed
                return first
            }
        }

        if let inProgressItem = first(where: { isInProgress($0) }) {
            return inProgressItem
        }

        return first
    }
}
