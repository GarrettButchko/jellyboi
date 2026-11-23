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
        return (type == .episode || type == .video || type == .trailer) ? MediaAspectRatio.thumbnail : MediaAspectRatio.poster
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
    ///
    /// Use this where the episode title is displayed separately, such as poster badges and the
    /// episode header capsule. Use `formattedEpisodeName` when the designation and title belong
    /// together in one string.
    var formattedEpisodeNumber: String? {
        guard type == .episode else { return nil }
        if let season = parentIndexNumber, let episode = indexNumber {
            return "S\(season) E\(episode)"
        } else if let episode = indexNumber {
            return "Ep \(episode)"
        }
        return nil
    }

    /// Canonical episode label: designation plus title, e.g. "S1 E2: Pilot".
    ///
    /// This is the single place episode titles get assembled. Context menus, the player, the lock
    /// screen, and Up Next all read it, so they can never disagree on ordering or punctuation.
    /// Returns nil for anything that is not an episode.
    var formattedEpisodeName: String? {
        guard type == .episode else { return nil }
        let designation = formattedEpisodeNumber
        let title = name.flatMap { $0.isEmpty ? nil : $0 }

        switch (designation, title) {
        case let (.some(designation), .some(title)):
            return "\(designation): \(title)"
        case let (.some(designation), .none):
            return designation
        case let (.none, .some(title)):
            return title
        case (.none, .none):
            return nil
        }
    }

    /// Formatted title suitable for context menus, action headers, and display labels.
    /// - Parameter includeSeriesName: When true, prefixes with the series name if available
    ///   (e.g. "Series • S1 E1: Pilot"). When false, omits it (e.g. "S1 E1: Pilot").
    func contextMenuTitle(includeSeriesName: Bool = true) -> String {
        guard type == .episode else { return name ?? "" }

        let episode = formattedEpisodeName ?? "Episode"
        guard includeSeriesName, let series = seriesName, !series.isEmpty else {
            return episode
        }
        return "\(series) • \(episode)"
    }

    /// Formatted title for media playback headers, lock screen, and player overlays.
    var playbackTitle: String {
        if type == .episode {
            return formattedEpisodeName ?? "Episode"
        }
        return name ?? "Video"
    }

    /// Formatted subtitle for media playback headers (e.g. series name or production year).
    var playbackSubtitle: String? {
        if type == .episode {
            return seriesName
        }
        if let year = productionYear {
            return String(year)
        }
        return nil
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

    /// Server-reported watch progress as a 0...1 ratio. Returns nil when no progress is recorded.
    ///
    /// This is the single source every other progress value below derives from.
    var watchProgress: Double? {
        if userData?.isPlayed == true { return 1.0 }
        guard let percent = userData?.playedPercentage else { return nil }
        return min(max(percent / 100.0, 0), 1.0)
    }

    /// Whether the server has marked the item as watched.
    ///
    /// Reads the server's `isPlayed` flag directly. No client-side percentage threshold: the server
    /// decides when something counts as played (its own configured threshold), so the app stays in
    /// agreement with Jellyfin and every other client.
    var isWatched: Bool {
        userData?.isPlayed == true
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

    /// Progress as an integer percentage, forced to 100 once the item counts as watched.
    ///
    /// `percentText`, `hasProgress`, and `isProgressVisible` all derive from this.
    var progressPercentage: Int {
        if isWatched { return 100 }
        guard let progress = watchProgress else { return 0 }
        return Int(progress * 100)
    }

    /// Formatted percentage label (e.g. "45%").
    var percentText: String {
        "\(progressPercentage)%"
    }

    /// Whether the item has positive playback progress.
    ///
    /// `progressPercentage` alone is not sufficient: some servers report position ticks without a
    /// played percentage, and ticks are the only signal available in that case.
    var hasProgress: Bool {
        if progressPercentage > 0 { return true }
        guard let ticks = userData?.playbackPositionTicks, ticks > 0 else { return false }
        let total = runTimeTicks.map { Int($0) } ?? 0
        return total > 0 ? (Double(ticks) / Double(total)) * 100.0 >= 1.0 : true
    }

    /// Whether the item is partially watched and not completed.
    var isInProgress: Bool {
        !isWatched && hasProgress
    }

    /// Whether a progress indicator (ring or bar) should be drawn. Watched items stay visible at 100%.
    var isProgressVisible: Bool {
        progressPercentage > 0
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
        if let unplayed = userData?.unplayedItemCount,
           let total = recursiveItemCount ?? episodeCount, total > 0, unplayed == total {
            return false
        }
        let showEpisodes = (allEpisodes.first?.seriesID == id) ? allEpisodes : allEpisodes.filter { $0.seriesID == id }
        if !showEpisodes.isEmpty {
            return showEpisodes.allSatisfy { $0.isWatched }
        }
        return false
    }

    /// Computes the series watch progress (0.0 to 1.0) matching the MediaDetailView progress ring.
    public func seriesWatchProgress(allEpisodes: [BaseItemDto] = []) -> Double? {
        guard type == .series else { return watchProgress }
        if isSeriesWatched(allEpisodes: allEpisodes) { return 1.0 }
        if let unplayed = userData?.unplayedItemCount,
           let total = recursiveItemCount ?? episodeCount, total > 0 {
            return max(0.0, min(1.0, Double(total - unplayed) / Double(total)))
        }
        let showEpisodes = (allEpisodes.first?.seriesID == id) ? allEpisodes : allEpisodes.filter { $0.seriesID == id }
        if !showEpisodes.isEmpty {
            return BaseItemDto.cumulativeProgress(for: showEpisodes, allEpisodes: showEpisodes)
        }
        return watchProgress
    }

    /// Evaluates whether a series is currently in-progress.
    public func isSeriesInProgress(allEpisodes: [BaseItemDto] = [], resumeShows: [BaseItemDto] = []) -> Bool {
        guard type == .series else { return isInProgress }
        if isSeriesWatched(allEpisodes: allEpisodes) { return false }
        if let unplayed = userData?.unplayedItemCount,
           let total = recursiveItemCount ?? episodeCount, total > 0 {
            if unplayed == total { return false }
            if unplayed < total { return true }
        }
        if resumeShows.contains(where: { $0.seriesID == id || $0.id == id }) {
            return true
        }
        let showEpisodes = (allEpisodes.first?.seriesID == id) ? allEpisodes : allEpisodes.filter { $0.seriesID == id }
        if !showEpisodes.isEmpty {
            return showEpisodes.contains { $0.isWatched || $0.isInProgress }
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
            || !(parentBackdropImageTags ?? []).isEmpty
    }

    /// Whether an episode is the first episode of a show and has never been played.
    public var isUnplayedFirstEpisode: Bool {
        guard type == .episode else { return false }
        let isFirst = (parentIndexNumber ?? 1) <= 1 && (indexNumber ?? 1) <= 1
        let hasBeenPlayed = hasProgress || isWatched || (userData?.isPlayed == true)
        return isFirst && !hasBeenPlayed
    }

    /// Whether this item (or its parent series if an episode) has an artwork image with the title (Thumb image).
    public func hasImageWithTitle(
        allShows: [BaseItemDto] = [],
        seriesLookup: ((String) -> BaseItemDto?)? = nil
    ) -> Bool {
        if type == .episode {
            if seriesThumbImageTag != nil || parentThumbImageTag != nil {
                return true
            }
            if let sID = seriesID ?? parentThumbItemID ?? parentBackdropItemID {
                let series = seriesLookup?(sID) ?? allShows.first(where: { $0.id == sID })
                if let series {
                    return series.imageTags?.keys.contains("Thumb") == true || series.seriesThumbImageTag != nil
                }
            }
            return false
        }
        return imageTags?.keys.contains("Thumb") == true || seriesThumbImageTag != nil
    }

    /// Computes the artwork image URL that includes the title (Thumb image).
    /// Returns nil if the item has no image with title.
    public func imageWithTitleURL(
        client: JellyfinClient?,
        allShows: [BaseItemDto] = [],
        seriesLookup: ((String) -> BaseItemDto?)? = nil
    ) -> URL? {
        guard let client else { return nil }

        if type == .episode {
            let sID = seriesID ?? parentThumbItemID ?? parentBackdropItemID
            guard let sID else { return nil }
            let parentSeries = seriesLookup?(sID) ?? allShows.first(where: { $0.id == sID })
            let thumbTag = seriesThumbImageTag ?? parentThumbImageTag ?? parentSeries?.imageTags?["Thumb"] ?? parentSeries?.seriesThumbImageTag
            guard thumbTag != nil || parentSeries?.imageTags?.keys.contains("Thumb") == true else {
                return nil
            }
            return client.itemImageURL(
                itemID: sID,
                imageType: "Thumb",
                parameters: .backdrop(maxWidth: 800, quality: 70, tag: thumbTag)
            )
        }

        guard hasImageWithTitle(allShows: allShows, seriesLookup: seriesLookup) else { return nil }
        let tag = imageTags?["Thumb"] ?? seriesThumbImageTag
        guard let id else { return nil }
        return client.itemImageURL(
            itemID: id,
            imageType: "Thumb",
            parameters: .backdrop(maxWidth: 800, quality: 70, tag: tag)
        )
    }

    /// Computes the backdrop/hero URL for the item using the given client.
    /// Prefers the Thumb image (which includes the series or movie title embedded in the artwork).
    /// If there is no image with title, returns nil so non-title images are not shown in carousel.
    public func backdropURL(client: JellyfinClient?) -> URL? {
        guard let client else { return nil }

        if type == .episode {
            let sID = seriesID ?? parentThumbItemID ?? parentBackdropItemID
            guard let sID else { return nil }
            let thumbTag = seriesThumbImageTag ?? parentThumbImageTag
            if thumbTag != nil {
                return client.itemImageURL(
                    itemID: sID,
                    imageType: "Thumb",
                    parameters: .backdrop(maxWidth: 800, quality: 70, tag: thumbTag)
                )
            }
            return client.itemImageURL(
                itemID: sID,
                imageType: "Thumb",
                parameters: .backdrop(maxWidth: 800, quality: 70)
            )
        }

        guard hasImageWithTitle() else { return nil }
        let tag = imageTags?["Thumb"] ?? seriesThumbImageTag
        guard let id else { return nil }
        return client.itemImageURL(
            itemID: id,
            imageType: "Thumb",
            parameters: .backdrop(maxWidth: 800, quality: 70, tag: tag)
        )
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

    /// Computes the season poster URL for an episode using the given client.
    public func seasonPosterURL(
        client: JellyfinClient?,
        parameters: Paths.GetItemImageParameters = .poster()
    ) -> URL? {
        guard let client, let seasonID else { return nil }
        return client.itemImageURL(itemID: seasonID, parameters: parameters)
    }

    /// Computes the backdrop image URL for an item using the given client.
    public func backdropImageURL(
        client: JellyfinClient?,
        parameters: Paths.GetItemImageParameters = .backdrop(maxWidth: 800, quality: 90)
    ) -> URL? {
        guard let client, let id else { return nil }
        guard (backdropImageTags?.isEmpty == false) || imageTags?.keys.contains("Backdrop") == true else { return nil }
        return client.itemImageURL(
            itemID: id,
            imageType: "Backdrop",
            parameters: parameters
        )
    }

    /// Resolves an ordered list of artwork candidate URLs for playback metadata, lock screen, and Now Playing info.
    /// Ordered by priority: poster -> detail poster -> series poster -> season poster -> thumbnail -> backdrop.
    public func artworkURLs(client: JellyfinClient?) -> [URL] {
        guard let client else { return [] }
        var urls: [URL] = []

        // 1. Poster URL (matches the card / detail cache key)
        if let poster = posterURL(client: client) {
            urls.append(poster)
        }

        // 2. High-resolution detail poster
        if let detailPoster = posterURL(client: client, parameters: .detailPoster()), !urls.contains(detailPoster) {
            urls.append(detailPoster)
        }

        // 3. For episodes, fallback to series or season poster
        if type == .episode {
            if let seriesPoster = seriesPosterURL(client: client, parameters: .detailPoster()), !urls.contains(seriesPoster) {
                urls.append(seriesPoster)
            }
            if let seasonPoster = seasonPosterURL(client: client, parameters: .detailPoster()), !urls.contains(seasonPoster) {
                urls.append(seasonPoster)
            }
        }

        // 4. Thumb / Wide thumbnail fallback
        if let thumb = thumbnailURL(client: client), !urls.contains(thumb) {
            urls.append(thumb)
        }

        // 5. Backdrop fallback
        if let backdrop = backdropImageURL(client: client), !urls.contains(backdrop) {
            urls.append(backdrop)
        }

        return urls
    }


}

extension BaseItemPerson {
    /// Computes the avatar image URL for a person.
    public func avatarURL(client: JellyfinClient?) -> URL? {
        guard let client, let id, primaryImageTag != nil else { return nil }
        return client.itemImageURL(itemID: id, parameters: .avatar(tag: primaryImageTag))
    }
}

extension Sequence where Element == BaseItemDto {
    /// Sorts episodes by season number (parentIndexNumber) and episode number (indexNumber).
    func sortedBySeasonAndEpisode() -> [BaseItemDto] {
        sorted { a, b in
            let sA = a.parentIndexNumber ?? 1
            let sB = b.parentIndexNumber ?? 1
            if sA != sB { return sA < sB }
            return (a.indexNumber ?? 1) < (b.indexNumber ?? 1)
        }
    }
}

extension Array where Element == BaseItemDto {
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

    /// Determines the next playable item ID in an ordered sequence of media items (e.g. episodes or collection items).
    /// - If `fromBeginning` is true, returns the first item ID.
    /// - If any items were completed, returns the first in-progress or unplayed item ID after the latest completed item.
    /// - If no item was completed yet, returns the first in-progress item ID, or the first item ID if none started.
    /// - If all items are completed, restarts from the first item ID.
    func nextPlayableID(fromBeginning: Bool = false) -> String? {
        guard !isEmpty else { return nil }
        if fromBeginning {
            return first?.id
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
                    return inProgressItem.id
                }
                return remaining.first?.id
            } else {
                // All items completed
                return first?.id
            }
        }

        if let inProgressItem = first(where: { isInProgress($0) }) {
            return inProgressItem.id
        }

        return first?.id
    }
}

// MARK: - Navigation Transition Helpers

extension BaseItemDto {
    /// Generates a unique transition identifier for navigation zoom animations.
    /// - Parameters:
    ///   - isCarousel: Whether the item is displayed in the hero carousel.
    ///   - rowKey: An optional row identifier (e.g. section row id) to distinguish shelf items.
    /// - Returns: An `AnyHashable` identifier to use with `matchedTransitionSource` and `.zoom(sourceID:)`.
    public func zoomTransitionID(isCarousel: Bool = false, rowKey: String? = nil) -> AnyHashable {
        let identifier = id ?? ""
        if isCarousel {
            return AnyHashable("carousel-\(identifier)")
        }
        if let rowKey {
            return AnyHashable("\(rowKey)-\(identifier)")
        }
        return identifier.isEmpty ? AnyHashable(self) : AnyHashable(identifier)
    }

    /// Generates a unique transition identifier for navigation zoom animations from an optional item ID.
    public static func zoomTransitionID(itemID: String?, isCarousel: Bool = false, rowKey: String? = nil) -> AnyHashable {
        let identifier = itemID ?? ""
        if isCarousel {
            return AnyHashable("carousel-\(identifier)")
        }
        if let rowKey {
            return AnyHashable("\(rowKey)-\(identifier)")
        }
        return AnyHashable(identifier)
    }
}

