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

    // MARK: - Title & Presentation Helpers

    /// Formatted season and episode designation (e.g. "S1 E2" or "Ep 2") for episodes.
    var formattedEpisodeNumber: String? {
        guard type == .episode else { return nil }
        if let season = parentIndexNumber, let episode = indexNumber {
            return "S\(season) E\(episode)"
        } else if let episode = indexNumber {
            return "Ep \(episode)"
        }
        return nil
    }

    /// Formatted title suitable for context menus, action headers, and display labels.
    /// For episodes, formats with series name (optional), season/episode numbers, and episode title.
    /// - Parameter includeSeriesName: When true, prefixes with the series name if available (e.g. "Series • S1 E1: Pilot").
    ///   When false, excludes the series name (e.g. "S1 E1: Pilot").
    func contextMenuTitle(includeSeriesName: Bool = true) -> String {
        if type == .episode {
            let epNumber = formattedEpisodeNumber
            let epName = name
            let series = includeSeriesName ? seriesName : nil

            switch (series, epNumber, epName) {
            case let (.some(s), .some(e), .some(n)) where !s.isEmpty && !e.isEmpty && !n.isEmpty:
                return "\(s) • \(e): \(n)"
            case let (_, .some(e), .some(n)) where !e.isEmpty && !n.isEmpty:
                return includeSeriesName ? "\(e) • \(n)" : "\(e): \(n)"
            case let (.some(s), _, .some(n)) where !s.isEmpty && !n.isEmpty:
                return "\(s) • \(n)"
            case let (_, .some(e), _):
                return e
            case let (_, _, .some(n)) where !n.isEmpty:
                return n
            default:
                return "Episode"
            }
        }
        return name ?? ""
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

    // MARK: - Image URLs

    /// Whether this item has a backdrop or thumb image available.
    public var hasBackdrop: Bool {
        !(backdropImageTags ?? []).isEmpty
            || imageTags?.keys.contains("Backdrop") == true
            || imageTags?.keys.contains("Thumb") == true
    }

    /// Computes the poster URL for the item using the given client.
    /// For episodes without a primary image tag, falls back to the series poster URL.
    public func posterURL(
        client: JellyfinClient?,
        parameters: Paths.GetItemImageParameters = .poster()
    ) -> URL? {
        guard let client, let id else { return nil }
        if type == .episode && (imageTags?.keys.contains("Primary") != true) {
            return seriesPosterURL(client: client, parameters: parameters)
        }
        return client.itemImageURL(itemID: id, parameters: parameters)
    }

    /// Computes the series poster URL for an episode or series using the given client.
    public func seriesPosterURL(
        client: JellyfinClient?,
        parameters: Paths.GetItemImageParameters = .poster()
    ) -> URL? {
        guard let client else { return nil }
        let targetID = seriesID ?? id
        guard let targetID else { return nil }
        return client.itemImageURL(itemID: targetID, parameters: parameters)
    }

    /// Computes the wide thumbnail URL for an episode, video, or special feature.
    public func thumbnailURL(
        client: JellyfinClient?,
        parameters: Paths.GetItemImageParameters = .thumbnail()
    ) -> URL? {
        guard let client, let id else { return nil }
        let imageType = imageTags?.keys.contains("Thumb") == true ? "Thumb" : "Primary"
        return client.itemImageURL(
            itemID: id,
            imageType: imageType,
            parameters: parameters
        )
    }

    /// Computes the hero/detail artwork URL for display on detail views (wide thumbnail for episodes, detail poster for others).
    public func detailPosterURL(client: JellyfinClient?) -> URL? {
        if type == .episode {
            return thumbnailURL(client: client, parameters: .thumbnail(maxWidth: 360, quality: 65))
        }
        return posterURL(client: client, parameters: .detailPoster())
    }

    /// Computes the backdrop URL for the item using the given client.
    /// Prefers Thumb, then Backdrop, then episode Primary, then series Thumb, then Backdrop.
    public func backdropURL(client: JellyfinClient?) -> URL? {
        guard let client, let id else { return nil }
        let hasThumb = imageTags?.keys.contains("Thumb") == true
        let hasBackdrop = !(backdropImageTags ?? []).isEmpty || imageTags?.keys.contains("Backdrop") == true
        let imageType: String
        let targetID: String

        if hasThumb {
            imageType = "Thumb"
            targetID = id
        } else if hasBackdrop {
            imageType = "Backdrop"
            targetID = id
        } else if type == .episode, imageTags?.keys.contains("Primary") == true {
            imageType = "Primary"
            targetID = id
        } else if let seriesID {
            imageType = "Thumb"
            targetID = seriesID
        } else {
            imageType = "Backdrop"
            targetID = id
        }

        return client.itemImageURL(
            itemID: targetID,
            imageType: imageType,
            parameters: .backdrop(maxWidth: 800, quality: 70)
        )
    }
}

extension BaseItemPerson {
    /// Computes the avatar image URL for a person.
    public func avatarURL(client: JellyfinClient?) -> URL? {
        guard let client, let id, primaryImageTag != nil else { return nil }
        return client.itemImageURL(itemID: id, parameters: .avatar(tag: primaryImageTag))
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
