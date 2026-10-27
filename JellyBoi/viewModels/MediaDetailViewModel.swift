//
//  MediaDetailViewModel.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 9/2/26.
//

import SwiftUI
import Observation
import Get
import JellyfinAPI
import BaseColors
import LoggingKit

@Observable
@MainActor
class MediaDetailViewModel {

    // MARK: - State

    var detailedItem: BaseItemDto?
    var sourceItem: BaseItemDto?
    var seriesItem: BaseItemDto?
    var similarItems: [BaseItemDto] = []
    var seasons: [BaseItemDto] = []
    var episodes: [BaseItemDto] = []
    var collectionItems: [BaseItemDto] = []
    var selectedSeasonIndex: Int = 0
    var scrolledEpisodeID: String?
    var hasInitialEpisodeScrolled: Bool = false
    var heroAspectRatio: CGFloat = 2.0 / 3.0
    var hasDetectedBitmapRatio = false
    var heroReady = false
    var isLoading = false
    var isLoadingCollectionItems = false
    var isLoadingEpisodes = false
    private var client: JellyfinClient?
    private weak var libraryViewModel: LibraryViewModel?
    private static var collectionItemsCache: [String: [BaseItemDto]] = [:]

    // MARK: - Playback Configuration (Video Quality / Bitrate, Audio, Subtitles)

    struct QualityOption: Identifiable, Hashable {
        let id: String
        let label: String
        let mediaSourceID: String?
        let maxBitrate: Int?
    }

    var mediaSources: [MediaSourceInfo] = []
    var selectedMediaSourceID: String?
    var selectedMaxBitrate: Int?
    var selectedAudioStreamIndex: Int?
    var selectedSubtitleStreamIndex: Int? = -1
    var isLoadingPlaybackOptions = false

    init(item: BaseItemDto? = nil) {
        if let item {
            self.sourceItem = item
            if item.type == .boxSet, let id = item.id, let cached = Self.collectionItemsCache[id] {
                self.collectionItems = cached
            }
            if item.type == .series {
                self.isLoadingEpisodes = true
            }
            if let ratio = item.primaryImageAspectRatio, ratio > 0 {
                self.heroAspectRatio = CGFloat(ratio)
            } else if item.type == .episode {
                self.heroAspectRatio = 16.0 / 9.0
            }
            if let sources = item.mediaSources, !sources.isEmpty {
                self.mediaSources = sources
                configureInitialStreamSelection()
            }
        }
    }

    var displayItem: BaseItemDto? {
        detailedItem ?? sourceItem
    }

    func playableItem(libraryViewModel: LibraryViewModel?, fromBeginning: Bool = false) -> BaseItemDto {
        var currentItem = displayItem ?? BaseItemDto()
        if currentItem.type == .series || currentItem.type == .boxSet {
            return nextPlayableEpisode(libraryViewModel: libraryViewModel, fromBeginning: fromBeginning) ?? currentItem
        }
        if let id = currentItem.id,
           currentItem.resumePlaybackTicks == 0,
           let matching = libraryViewModel?.movies.first(where: { $0.id == id }) ?? libraryViewModel?.resumeShows.first(where: { $0.id == id }),
           matching.resumePlaybackTicks > 0 {
            currentItem.userData = matching.userData
        }
        return currentItem
    }

    func shouldShowOptionsButton(libraryViewModel: LibraryViewModel?) -> Bool {
        guard let currentItem = displayItem else { return true }
        if currentItem.type == .boxSet {
            return false
        }
        if currentItem.type == .series {
            return false
        }
        return true
    }

    func isOptionsDisabled(libraryViewModel: LibraryViewModel?) -> Bool {
        guard let currentItem = displayItem else { return false }
        if currentItem.type == .boxSet {
            return isLoadingCollectionItems || collectionItems.isEmpty
        }
        return false
    }

    func isPlayDisabled(libraryViewModel: LibraryViewModel?) -> Bool {
        guard let currentItem = displayItem else { return false }
        if currentItem.type == .boxSet {
            return isLoadingCollectionItems || collectionItems.isEmpty
        }
        return false
    }

    func shouldShowSeriesButton(cameFromShow: Bool) -> Bool {
        guard let currentItem = displayItem else { return false }
        let type = currentItem.type
        guard !cameFromShow && type == .episode else { return false }
        return currentItem.seriesID != nil
    }

    func parentSeries(libraryViewModel: LibraryViewModel?) -> BaseItemDto? {
        if let series = seriesItem {
            return series
        }
        guard let seriesID = displayItem?.seriesID else { return nil }
        if let found = libraryViewModel?.tvShows.first(where: { $0.id == seriesID }) {
            return found
        }
        return BaseItemDto(
            id: seriesID,
            name: displayItem?.seriesName,
            type: .series
        )
    }

    var hasExtraInfo: Bool {
        guard let item = displayItem else { return false }
        let people = item.people ?? []
        return !(item.genres ?? []).isEmpty
            || !people.filter({ $0.type == .director }).isEmpty
            || !people.filter({ $0.type == .writer }).isEmpty
            || !(item.studios ?? []).isEmpty
    }

    func playMedia(
        fromBeginning: Bool,
        playbackManager: PlaybackManager,
        serverViewModel: ServerViewModel,
        libraryViewModel: LibraryViewModel
    ) {
        let itemToPlay = playableItem(libraryViewModel: libraryViewModel, fromBeginning: fromBeginning)
        let queue: [BaseItemDto]? = {
            if displayItem?.type == .series, !episodes.isEmpty {
                return episodes
            }
            if displayItem?.type == .boxSet, !collectionItems.isEmpty {
                return collectionItems
            }
            return nil
        }()

        playbackManager.play(
            item: itemToPlay,
            fromBeginning: fromBeginning,
            client: serverViewModel.client,
            userID: serverViewModel.currentUser?.id,
            libraryViewModel: libraryViewModel,
            mediaSourceID: selectedMediaSourceID,
            audioStreamIndex: selectedAudioStreamIndex,
            subtitleStreamIndex: selectedSubtitleStreamIndex,
            maxBitrate: selectedMaxBitrate,
            queue: queue
        )
    }

    // MARK: - Server-derived Playback State

    var currentPlaybackTargetItem: BaseItemDto? {
        if displayItem?.type == .series || displayItem?.type == .boxSet {
            return nextPlayableEpisode(libraryViewModel: libraryViewModel)
        }
        return displayItem
    }

    var isCollectionWatched: Bool {
        guard displayItem?.type == .boxSet, !collectionItems.isEmpty else { return false }
        return collectionItems.allSatisfy { $0.isWatched }
    }

    var isSeriesWatched: Bool {
        guard displayItem?.type == .series else { return false }
        if let unplayed = displayItem?.userData?.unplayedItemCount, unplayed == 0 { return true }
        if displayItem?.userData?.isPlayed == true { return true }
        if !episodes.isEmpty {
            return episodes.allSatisfy { $0.isWatched }
        }
        return displayItem?.isSeriesWatched(allEpisodes: libraryViewModel?.episodes ?? []) ?? false
    }

    var isWatched: Bool {
        if displayItem?.type == .boxSet {
            return isCollectionWatched
        }
        if displayItem?.type == .series {
            return isSeriesWatched
        }
        return displayItem?.isWatched ?? false
    }

    private func cumulativeProgress(for items: [BaseItemDto]) -> Double {
        BaseItemDto.cumulativeProgress(for: items, allEpisodes: libraryViewModel?.episodes ?? [])
    }

    var hasProgress: Bool {
        if isWatched { return false }
        return (watchProgress ?? 0) > 0
    }

    var isInProgress: Bool {
        if isWatched { return false }
        if displayItem?.type == .boxSet {
            return collectionItems.contains { $0.isWatched || $0.isInProgress }
        }
        if displayItem?.type == .series {
            if !episodes.isEmpty {
                return episodes.contains { $0.isWatched || $0.isInProgress }
            }
            return displayItem?.isSeriesInProgress(
                allEpisodes: libraryViewModel?.episodes ?? [],
                resumeShows: libraryViewModel?.resumeShows ?? []
            ) ?? false
        }
        return displayItem?.isInProgress ?? false
    }

    var watchProgress: Double? {
        if isWatched { return 1.0 }
        if displayItem?.type == .boxSet {
            if !collectionItems.isEmpty {
                return cumulativeProgress(for: collectionItems)
            }
            return 0.0
        }
        if displayItem?.type == .series {
            if !episodes.isEmpty {
                return cumulativeProgress(for: episodes)
            }
            return displayItem?.seriesWatchProgress(allEpisodes: libraryViewModel?.episodes ?? []) ?? 0.0
        }
        return displayItem?.watchProgress
    }

    var progressVisible: Bool {
        if displayItem?.type == .boxSet { return false }
        if isWatched { return true }
        guard let wp = watchProgress else { return false }
        return Int(wp * 100) > 0
    }

    var progressValue: Double {
        if isWatched { return 1.0 }
        return watchProgress ?? 0.0
    }

    var percentText: String {
        if isWatched { return "100%" }
        if displayItem?.type == .boxSet || displayItem?.type == .series {
            if let wp = watchProgress {
                return "\(Int(wp * 100))%"
            }
            return "0%"
        }
        return displayItem?.percentText ?? ""
    }

    func targetPlayableTitle(libraryViewModel: LibraryViewModel?) -> String {
        let target = playableItem(libraryViewModel: libraryViewModel)
        if target.type == .episode {
            var epTitle: String? = nil
            if let season = target.parentIndexNumber, let episode = target.indexNumber {
                epTitle = "S\(season) E\(episode)"
            } else if let episode = target.indexNumber {
                epTitle = "Ep \(episode)"
            }

            let name = target.name

            switch (epTitle, name) {
            case let (.some(e), .some(n)) where !e.isEmpty && !n.isEmpty:
                return "\(e): \(n)"
            case let (.some(e), _):
                return e
            case let (_, .some(n)) where !n.isEmpty:
                return n
            default:
                return target.name ?? "Episode"
            }
        }

        if let targetName = target.name, !targetName.isEmpty {
            return targetName
        }
        return displayItem?.name ?? ""
    }

    var contextMenuTitle: String {
        targetPlayableTitle(libraryViewModel: nil)
    }

    func handlePlayTap(
        playbackManager: PlaybackManager,
        serverViewModel: ServerViewModel,
        libraryViewModel: LibraryViewModel
    ) {
        if isPlayDisabled(libraryViewModel: libraryViewModel) {
            return
        }
        if isWatched {
            playMedia(
                fromBeginning: true,
                playbackManager: playbackManager,
                serverViewModel: serverViewModel,
                libraryViewModel: libraryViewModel
            )
        } else {
            playMedia(
                fromBeginning: false,
                playbackManager: playbackManager,
                serverViewModel: serverViewModel,
                libraryViewModel: libraryViewModel
            )
        }
    }

    enum SeriesConfirmationAlert {
        case startFromBeginning
        case resetProgress
    }

    var seriesAlertAction: SeriesConfirmationAlert?

    func resetSeriesProgress(serverViewModel: ServerViewModel?) {
        guard let item = displayItem, let itemID = item.id else { return }
        withAnimation(.smooth) {
            clearProgress(for: itemID)
            for index in episodes.indices {
                episodes[index].clearProgress()
            }
        }
        Task {
            await serverViewModel?.resetProgress(for: item)
            if let client = serverViewModel?.client, let userID = serverViewModel?.currentUser?.id {
                let inProgressOrPlayed = episodes.filter { $0.isWatched || $0.hasProgress }
                for ep in inProgressOrPlayed {
                    if let epID = ep.id {
                        _ = try? await client.send(Paths.markUnplayedItem(itemID: epID, userID: userID))
                    }
                }
            }
        }
    }

    func startSeriesFromBeginning(
        playbackManager: PlaybackManager,
        serverViewModel: ServerViewModel,
        libraryViewModel: LibraryViewModel
    ) {
        resetSeriesProgress(serverViewModel: serverViewModel)

        let firstEpisode = episodes.first(where: { ($0.parentIndexNumber ?? 1) >= 1 && ($0.indexNumber ?? 1) == 1 })
            ?? episodes.first(where: { ($0.parentIndexNumber ?? 1) >= 1 })
            ?? episodes.first
            ?? playableItem(libraryViewModel: libraryViewModel, fromBeginning: true)

        playbackManager.play(
            item: firstEpisode,
            fromBeginning: true,
            client: serverViewModel.client,
            userID: serverViewModel.currentUser?.id,
            libraryViewModel: libraryViewModel,
            mediaSourceID: selectedMediaSourceID,
            audioStreamIndex: selectedAudioStreamIndex,
            subtitleStreamIndex: selectedSubtitleStreamIndex,
            maxBitrate: selectedMaxBitrate,
            queue: !episodes.isEmpty ? episodes : nil
        )
    }

    func resetProgress(serverViewModel: ServerViewModel?) {
        guard let item = displayItem, let itemID = item.id else { return }
        if item.type == .series {
            resetSeriesProgress(serverViewModel: serverViewModel)
            return
        }
        withAnimation(.smooth) {
            clearProgress(for: itemID)
        }
        Task {
            await serverViewModel?.resetProgress(for: item)
        }
    }

    // MARK: - Download State & Actions

    enum DownloadAlertAction {
        case cancel
        case delete
    }

    var downloadAlertAction: DownloadAlertAction?

    func isShowFullyDownloaded(downloadManager: DownloadManager, libraryViewModel: LibraryViewModel?) -> Bool {
        guard let item = displayItem, item.type == .series, let showID = item.id else { return false }

        if !episodes.isEmpty {
            return episodes.allSatisfy { ep in
                guard let epID = ep.id else { return false }
                return downloadManager.isDownloaded(id: epID)
            }
        }

        let total = item.recursiveItemCount ?? (libraryViewModel?.tvShows.first(where: { $0.id == showID })?.recursiveItemCount)
        if let total, total > 0 {
            let downloadedCount = downloadManager.completedDownloads.filter {
                $0.item.seriesID == showID || $0.item.parentBackdropItemID == showID
            }.count
            return downloadedCount >= total
        }

        return false
    }

    func isShowDownloading(downloadManager: DownloadManager) -> Bool {
        guard let item = displayItem, item.type == .series, let showID = item.id else { return false }
        return downloadManager.activeDownloads.contains(where: { $0.group?.id == showID })
    }

    func isCollectionFullyDownloaded(downloadManager: DownloadManager) -> Bool {
        guard let item = displayItem, item.type == .boxSet, let _ = item.id else { return false }
        guard !collectionItems.isEmpty else { return false }
        return collectionItems.allSatisfy { ci in
            guard let id = ci.id else { return false }
            return downloadManager.isDownloaded(id: id)
        }
    }

    func isCollectionDownloading(downloadManager: DownloadManager) -> Bool {
        guard let item = displayItem, item.type == .boxSet, let collectionID = item.id else { return false }
        return downloadManager.activeDownloads.contains(where: { $0.group?.id == collectionID })
    }

    func collectionDownloadProgress(downloadManager: DownloadManager) -> Double {
        guard let item = displayItem, item.type == .boxSet, let collectionID = item.id else { return 0 }
        let downloading = downloadManager.activeDownloads.filter {
            $0.group?.id == collectionID
        }
        guard !downloading.isEmpty else { return 0 }

        let completed = downloadManager.completedDownloads.filter {
            $0.group?.id == collectionID
        }
        let totalCount = downloading.count + completed.count
        guard totalCount > 0 else { return 0 }

        let totalProgress = Double(completed.count) + downloading.reduce(0.0) { $0 + $1.progress }
        return totalProgress / Double(totalCount)
    }

    func showEpisodesLeft(downloadManager: DownloadManager) -> Int {
        guard let item = displayItem, item.type == .series, let showID = item.id else { return 0 }

        return downloadManager.activeDownloads.filter {
            $0.group?.id == showID
        }.count
    }

    func episodesLeft(downloadManager: DownloadManager) -> Int? {
        guard displayItem?.type == .series else { return nil }
        let count = showEpisodesLeft(downloadManager: downloadManager)
        return count > 0 ? count : nil
    }

    func showDownloadProgress(downloadManager: DownloadManager) -> Double {
        guard let item = displayItem, item.type == .series, let showID = item.id else { return 0 }

        let downloading = downloadManager.activeDownloads.filter {
            $0.group?.id == showID
        }
        guard !downloading.isEmpty else { return 0 }

        let completed = downloadManager.completedDownloads.filter {
            $0.group?.id == showID
        }
        let totalCount = downloading.count + completed.count
        guard totalCount > 0 else { return 0 }

        let totalProgress = Double(completed.count) + downloading.reduce(0.0) { $0 + $1.progress }
        return totalProgress / Double(totalCount)
    }

    func isDetailDownloaded(downloadManager: DownloadManager, libraryViewModel: LibraryViewModel?) -> Bool {
        if displayItem?.type == .series {
            return isShowFullyDownloaded(downloadManager: downloadManager, libraryViewModel: libraryViewModel)
        } else if displayItem?.type == .boxSet {
            return isCollectionFullyDownloaded(downloadManager: downloadManager)
        }
        let playable = playableItem(libraryViewModel: libraryViewModel)
        return downloadManager.isDownloaded(id: playable.id ?? "")
    }

    func isDetailDownloading(downloadManager: DownloadManager) -> Bool {
        if displayItem?.type == .series {
            return isShowDownloading(downloadManager: downloadManager)
        } else if displayItem?.type == .boxSet {
            return isCollectionDownloading(downloadManager: downloadManager)
        }
        let playable = playableItem(libraryViewModel: nil)
        return downloadManager.isDownloading(id: playable.id ?? "")
    }

    func detailDownloadProgress(downloadManager: DownloadManager, libraryViewModel: LibraryViewModel?) -> Double {
        if displayItem?.type == .series {
            return showDownloadProgress(downloadManager: downloadManager)
        } else if displayItem?.type == .boxSet {
            return collectionDownloadProgress(downloadManager: downloadManager)
        }
        let playable = playableItem(libraryViewModel: libraryViewModel)
        return downloadManager.progress(for: playable.id ?? "") ?? 0.0
    }

    @discardableResult
    func handleDownloadTap(
        downloadManager: DownloadManager,
        client: JellyfinClient?,
        libraryViewModel: LibraryViewModel?
    ) -> DownloadAlertAction? {
        let action: DownloadAlertAction?
        if displayItem?.type == .series {
            if isShowFullyDownloaded(downloadManager: downloadManager, libraryViewModel: libraryViewModel) {
                action = .delete
            } else if isShowDownloading(downloadManager: downloadManager) {
                action = .cancel
            } else if let client {
                let uncompletedEpisodes = episodes.filter { ep in
                    guard let epID = ep.id else { return false }
                    return !downloadManager.isDownloaded(id: epID) && !downloadManager.isDownloading(id: epID)
                }
                let groupInfo = DownloadGroupInfo(
                    id: displayItem?.id ?? "",
                    title: displayItem?.name ?? "Show",
                    type: .show,
                    primaryImageTag: displayItem?.imageTags?["Primary"]
                )
                downloadManager.startDownloads(items: uncompletedEpisodes, client: client, group: groupInfo)
                action = nil
            } else {
                action = nil
            }
        } else if displayItem?.type == .boxSet {
            if isCollectionFullyDownloaded(downloadManager: downloadManager) {
                action = .delete
            } else if isCollectionDownloading(downloadManager: downloadManager) {
                action = .cancel
            } else if let client {
                let collectionID = displayItem?.id ?? ""
                let collectionName = displayItem?.name ?? "Collection"
                let groupInfo = DownloadGroupInfo(
                    id: collectionID,
                    title: collectionName,
                    type: .collection,
                    primaryImageTag: displayItem?.imageTags?["Primary"]
                )
                let startItems: ([BaseItemDto]) -> Void = { items in
                    let uncompletedItems: [BaseItemDto] = items.compactMap { item in
                        guard let itemID = item.id, !downloadManager.isDownloaded(id: itemID), !downloadManager.isDownloading(id: itemID) else { return nil }
                        return item
                    }
                    downloadManager.startDownloads(items: uncompletedItems, client: client, group: groupInfo)
                }

                if collectionItems.isEmpty {
                    Task {
                        await self.loadCollectionItems(client: client, userID: nil)
                        startItems(self.collectionItems)
                    }
                } else {
                    startItems(collectionItems)
                }
                action = nil
            } else {
                action = nil
            }
        } else {
            let playable = playableItem(libraryViewModel: libraryViewModel)
            if let itemID = playable.id {
                if downloadManager.isDownloaded(id: itemID) {
                    action = .delete
                } else if downloadManager.isDownloading(id: itemID) {
                    action = .cancel
                } else if let client {
                    downloadManager.startDownload(item: playable, client: client, group: nil)
                    action = nil
                } else {
                    action = nil
                }
            } else {
                action = nil
            }
        }
        self.downloadAlertAction = action
        return action
    }

    func cancelDownload(downloadManager: DownloadManager) {
        if displayItem?.type == .series {
            guard let showID = displayItem?.id else { return }
            let idsToCancel = downloadManager.activeDownloads
                .filter { $0.group?.id == showID }
                .map(\.id)
            downloadManager.cancelDownloads(ids: idsToCancel)
        } else if displayItem?.type == .boxSet {
            guard let collectionID = displayItem?.id else { return }
            let idsToCancel = downloadManager.activeDownloads
                .filter { $0.group?.id == collectionID }
                .map(\.id)
            downloadManager.cancelDownloads(ids: idsToCancel)
        } else if let itemID = playableItem(libraryViewModel: nil).id {
            downloadManager.cancelDownload(id: itemID)
        }
    }

    func deleteDownload(downloadManager: DownloadManager) {
        if displayItem?.type == .series {
            guard let showID = displayItem?.id else { return }
            let episodeIDs = Set(episodes.compactMap(\.id))
            let idsToDelete = downloadManager.completedDownloads
                .filter {
                    $0.group?.id == showID ||
                    $0.item.seriesID == showID ||
                    $0.item.parentBackdropItemID == showID ||
                    episodeIDs.contains($0.id)
                }
                .map(\.id)
            downloadManager.deleteDownloads(ids: idsToDelete)
        } else if displayItem?.type == .boxSet {
            guard let collectionID = displayItem?.id else { return }
            let collectionItemIDs = Set(collectionItems.compactMap(\.id))
            let idsToDelete = downloadManager.completedDownloads
                .filter {
                    $0.group?.id == collectionID ||
                    collectionItemIDs.contains($0.id)
                }
                .map(\.id)
            downloadManager.deleteDownloads(ids: idsToDelete)
        } else if let itemID = playableItem(libraryViewModel: nil).id {
            downloadManager.deleteDownload(id: itemID)
        }
    }

    func downloadAlertItemName(libraryViewModel: LibraryViewModel?) -> String {
        if displayItem?.type == .series || displayItem?.type == .boxSet {
            return displayItem?.name ?? "this item"
        }
        let playable = playableItem(libraryViewModel: libraryViewModel)
        return playable.name ?? "this item"
    }

    var isFavorite: Bool {
        displayItem?.isFavorite ?? false
    }

    #if DEBUG
    var isOverviewHidden: Bool { DebugSettings.shared.hideOverview }
    var isCastHidden: Bool { DebugSettings.shared.hideCastAndCrew }
    var areTagsHidden: Bool { DebugSettings.shared.hideTags }
    var areSimilarItemsHidden: Bool { DebugSettings.shared.hideSimilarItems }
    #else
    var isOverviewHidden: Bool { false }
    var isCastHidden: Bool { false }
    var areTagsHidden: Bool { false }
    var areSimilarItemsHidden: Bool { false }
    #endif

    func isFavorite(fallback: BaseItemDto) -> Bool {
        displayItem?.isFavorite ?? fallback.isFavorite
    }

    func toggleFavorite(serverViewModel: ServerViewModel?, fallbackItem: BaseItemDto) async {
        guard let serverViewModel, let itemID = displayItem?.id ?? fallbackItem.id else { return }
        let current = isFavorite(fallback: fallbackItem)
        let newFavorite = !current
        detailedItem?.setFavorite(newFavorite)
        sourceItem?.setFavorite(newFavorite)
        let result = await serverViewModel.setFavorite(newFavorite, forItemID: itemID)
        if result == nil {
            detailedItem?.setFavorite(current)
            sourceItem?.setFavorite(current)
        }
    }

    var hasBackdrop: Bool {
        guard let item = displayItem else { return false }
        if let count = item.backdropImageTags?.count, count > 0 { return true }
        if item.imageTags?.keys.contains("Backdrop") == true { return true }
        if item.imageTags?.keys.contains("Thumb") == true { return true }
        return false
    }

    var backdropURL: URL? {
        backdropURL(client: nil)
    }

    func backdropURL(client fallbackClient: JellyfinClient? = nil) -> URL? {
        #if DEBUG
        if DebugSettings.shared.hideBackdrop { return nil }
        #endif
        return posterURL(client: fallbackClient)
    }

    var posterURL: URL? {
        posterURL(client: nil)
    }

    func posterURL(client fallbackClient: JellyfinClient? = nil) -> URL? {
        #if DEBUG
        if DebugSettings.shared.hidePoster { return nil }
        #endif
        let activeClient = client ?? fallbackClient
        guard let activeClient, let id = displayItem?.id else { return nil }
        if displayItem?.type == .episode {
            let imageType = displayItem?.imageTags?.keys.contains("Thumb") == true ? "Thumb" : "Primary"
            return activeClient.url(with: Paths.getItemImage(
                itemID: id,
                imageType: imageType,
                parameters: .init(maxWidth: 500, quality: 80)
            ))
        }
        return activeClient.url(with: Paths.getItemImage(
            itemID: id,
            imageType: "Primary",
            parameters: .init(maxWidth: 600, quality: 90)
        ))
    }

    func markHeroReady() {
        heroReady = true
    }

    func updateHeroAspectRatio(from size: CGSize) {
        guard size.height > 0 else { return }
        let ratio = size.width / size.height
        hasDetectedBitmapRatio = true
        if abs(heroAspectRatio - ratio) > 0.005 {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                heroAspectRatio = ratio
            }
        }
    }

    func prepare(item: BaseItemDto, client: JellyfinClient?, libraryViewModel: LibraryViewModel? = nil) {
        self.sourceItem = item
        self.client = client
        self.libraryViewModel = libraryViewModel
        self.hasInitialEpisodeScrolled = false
        self.scrolledEpisodeID = nil
        if item.type == .series {
            self.isLoadingEpisodes = true
            if let seriesID = item.id, let lvm = libraryViewModel {
                let cached = lvm.episodes.filter { $0.seriesID == seriesID }
                if !cached.isEmpty && self.episodes.isEmpty {
                    self.episodes = cached
                }
            }
        }
        if item.type == .boxSet, let collectionID = item.id {
            if let cached = Self.collectionItemsCache[collectionID], !cached.isEmpty && self.collectionItems.isEmpty {
                self.collectionItems = cached
            } else if self.collectionItems.isEmpty {
                self.isLoadingCollectionItems = true
            }
        }
        if let ratio = item.primaryImageAspectRatio, ratio > 0 {
            self.heroAspectRatio = CGFloat(ratio)
        } else if item.type == .episode {
            self.heroAspectRatio = 16.0 / 9.0
        }
        if let sources = item.mediaSources, !sources.isEmpty {
            self.mediaSources = sources
            configureInitialStreamSelection()
        }
    }

    func clearProgress(for itemID: String) {
        if displayItem?.id == itemID || displayItem?.seriesID == itemID {
            detailedItem?.clearProgress()
            sourceItem?.clearProgress()
        }
        episodes.clearProgress(for: itemID, matchingSeries: true)
        for index in collectionItems.indices {
            if collectionItems[index].id == itemID || itemID == displayItem?.id {
                collectionItems[index].clearProgress()
            }
        }
    }

    func handleFavoriteToggled(itemID: String, isFavorite: Bool) {
        if displayItem?.id == itemID {
            detailedItem?.setFavorite(isFavorite)
            sourceItem?.setFavorite(isFavorite)
        }
    }

    func load(item: BaseItemDto, client: JellyfinClient, userID: String?, libraryViewModel: LibraryViewModel) async {
        guard let itemID = item.id else { return }
        self.client = client
        self.libraryViewModel = libraryViewModel
        let resolvedItem = libraryViewModel.movies.first(where: { $0.id == itemID })
            ?? libraryViewModel.resumeShows.first(where: { $0.id == itemID })
            ?? libraryViewModel.episodes.first(where: { $0.id == itemID })
            ?? libraryViewModel.tvShows.first(where: { $0.id == itemID })
            ?? DownloadManager.shared.completedDownloads.first(where: { $0.item.id == itemID })?.item
            ?? item
        self.sourceItem = resolvedItem
        self.hasInitialEpisodeScrolled = false
        self.scrolledEpisodeID = nil
        isLoading = true
        defer { isLoading = false }

        if !NetworkMonitor.shared.isConnected {
            self.detailedItem = resolvedItem
            if let sources = detailedItem?.mediaSources ?? sourceItem?.mediaSources, !sources.isEmpty {
                self.mediaSources = sources
                configureInitialStreamSelection()
            }
            if item.type == .series || resolvedItem.type == .series {
                let downloadedEps = DownloadManager.shared.downloadedEpisodes
                    .filter { ($0.seriesID ?? $0.parentBackdropItemID) == itemID }
                    .sorted { ($0.indexNumber ?? 0) < ($1.indexNumber ?? 0) }
                self.episodes = downloadedEps
                let seasonNumbers = Set(downloadedEps.compactMap(\.parentIndexNumber))
                self.seasons = seasonNumbers.sorted().map { sNum in
                    BaseItemDto(id: "\(itemID)-season-\(sNum)", indexNumber: sNum, name: "Season \(sNum)", type: .season)
                }
            }
            isLoadingEpisodes = false
            return
        }

        async let detailResult: BaseItemDto? = {
            try? await client.send(Paths.getItem(itemID: itemID, userID: userID)).value
        }()
        async let similarResult: [BaseItemDto] = libraryViewModel.similarItems(
            for: itemID, client: client, userID: userID
        )

        // Load collection items / episodes concurrently so cumulative progress resolves immediately without waiting for details/similar
        if item.type == .series || resolvedItem.type == .series {
            await loadSeasonsAndEpisodes(client: client, userID: userID)
        } else {
            isLoadingEpisodes = false
            if item.type == .boxSet || resolvedItem.type == .boxSet {
                await loadCollectionItems(client: client, userID: userID, libraryViewModel: libraryViewModel)
            } else if item.type == .episode || resolvedItem.type == .episode {
                await loadParentSeries(client: client, userID: userID, libraryViewModel: libraryViewModel)
            }
        }

        detailedItem = await detailResult
        similarItems = await similarResult

        if let sources = detailedItem?.mediaSources ?? sourceItem?.mediaSources, !sources.isEmpty {
            self.mediaSources = sources
            configureInitialStreamSelection()
        }

        if !hasDetectedBitmapRatio, let ratio = detailedItem?.primaryImageAspectRatio, ratio > 0 {
            let newRatio = CGFloat(ratio)
            if abs(heroAspectRatio - newRatio) > 0.005 {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                    heroAspectRatio = newRatio
                }
            }
        }
    }

    // MARK: - Parent Series

    func loadParentSeries(client: JellyfinClient, userID: String?, libraryViewModel: LibraryViewModel) async {
        guard let seriesID = detailedItem?.seriesID ?? sourceItem?.seriesID else { return }
        if let local = libraryViewModel.tvShows.first(where: { $0.id == seriesID }) {
            self.seriesItem = local
            return
        }
        if let fetched = try? await client.send(Paths.getItem(itemID: seriesID, userID: userID)).value {
            self.seriesItem = fetched
        }
    }

    // MARK: - Seasons & Episodes

    func loadSeasonsAndEpisodes(client: JellyfinClient, userID: String?) async {
        guard let seriesID = sourceItem?.id else {
            isLoadingEpisodes = false
            return
        }
        isLoadingEpisodes = true
        defer { isLoadingEpisodes = false }

        let seasonResult = (try? await client.send(
            Paths.getSeasons(
                seriesID: seriesID,
                parameters: .init(
                    userID: userID,
                    fields: [.primaryImageAspectRatio],
                    enableImages: true,
                    enableUserData: false
                )
            )
        ).value.items) ?? []

        // Filter out specials and missing-season placeholders
        let filtered = seasonResult.filter { season in
            let num = season.indexNumber ?? season.parentIndexNumber ?? 0
            guard num != 0 else { return false }
            return season.type == .season
        }
        let sortedSeasons = (filtered.isEmpty ? seasonResult : filtered).sorted {
            let s0 = $0.indexNumber ?? $0.parentIndexNumber ?? 0
            let s1 = $1.indexNumber ?? $1.parentIndexNumber ?? 0
            return s0 < s1
        }
        seasons = sortedSeasons
        guard !seasons.isEmpty else { return }

        // Load all seasons' episodes in parallel to build continuous list
        let allEpisodes = await withTaskGroup(of: (Int, [BaseItemDto]).self) { group in
            for (index, season) in seasons.enumerated() {
                group.addTask {
                    let seasonNum = season.indexNumber ?? season.parentIndexNumber
                    let eps = (try? await client.send(
                        Paths.getEpisodes(
                            seriesID: seriesID,
                            parameters: .init(
                                userID: userID,
                                fields: [.primaryImageAspectRatio, .mediaSources, .mediaStreams],
                                season: seasonNum,
                                enableImages: true,
                                enableUserData: true
                            )
                        )
                    ).value.items) ?? []
                    return (index, eps)
                }
            }
            var dict: [Int: [BaseItemDto]] = [:]
            for await (index, eps) in group {
                dict[index] = eps
            }
            return dict.sorted { $0.key < $1.key }.map(\.value)
        }

        episodes = allEpisodes.flatMap { $0 }.sorted { a, b in
            let sA = seasonNumber(for: a)
            let sB = seasonNumber(for: b)
            if sA != sB {
                return sA < sB
            }
            let eA = a.indexNumber ?? 1
            let eB = b.indexNumber ?? 1
            if eA != eB {
                return eA < eB
            }
            return (a.premiereDate ?? .distantPast) < (b.premiereDate ?? .distantPast)
        }

        if let nextEp = nextPlayableEpisode(libraryViewModel: nil),
           let sIdx = seasonIndex(for: nextEp) {
            selectedSeasonIndex = sIdx
        } else {
            selectedSeasonIndex = 0
        }
    }

    func selectSeason(_ index: Int, client: JellyfinClient? = nil, userID: String? = nil) async {
        guard seasons.indices.contains(index) else { return }
        selectedSeasonIndex = index
    }

    func seasonNumber(for episode: BaseItemDto) -> Int {
        if let p = episode.parentIndexNumber { return p }
        if let sID = episode.seasonID,
           let s = seasons.first(where: { $0.id == sID }) {
            return s.indexNumber ?? s.parentIndexNumber ?? 1
        }
        return 1
    }

    func seasonIndex(for episode: BaseItemDto) -> Int? {
        if let sID = episode.seasonID, let idx = seasons.firstIndex(where: { $0.id == sID }) {
            return idx
        }
        let epSeasonNum = seasonNumber(for: episode)
        if let idx = seasons.firstIndex(where: { ($0.indexNumber ?? $0.parentIndexNumber) == epSeasonNum }) {
            return idx
        }
        if let sName = episode.seasonName, let idx = seasons.firstIndex(where: { $0.name == sName }) {
            return idx
        }
        return nil
    }

    func firstEpisode(forSeasonIndex index: Int) -> BaseItemDto? {
        guard seasons.indices.contains(index) else { return nil }
        let season = seasons[index]
        let targetSeasonNum = season.indexNumber ?? season.parentIndexNumber
        return episodes.first { ep in
            if let sID = season.id, let epSeasonID = ep.seasonID, sID == epSeasonID {
                return true
            }
            if let targetSeasonNum, seasonNumber(for: ep) == targetSeasonNum {
                return true
            }
            if let sName = season.name, let epSeasonName = ep.seasonName, !sName.isEmpty, sName == epSeasonName {
                return true
            }
            return false
        }
    }

    func nextPlayableEpisode(libraryViewModel: LibraryViewModel?, fromBeginning: Bool = false) -> BaseItemDto? {
        if displayItem?.type == .episode {
            return displayItem
        }
        if displayItem?.type == .movie {
            return displayItem
        }
        if displayItem?.type == .series {
            if !fromBeginning, let resumeEp = libraryViewModel?.resumeShows.first(where: { $0.seriesID == displayItem?.id }) {
                if let matched = episodes.first(where: { $0.id == resumeEp.id }) {
                    return matched
                }
                return resumeEp
            }
            return episodes.nextPlayableItem(fromBeginning: fromBeginning)
        }
        if displayItem?.type == .boxSet {
            let resolvedCollectionItems: [BaseItemDto] = collectionItems.map { ci in
                guard let id = ci.id else { return ci }
                return libraryViewModel?.movies.first(where: { $0.id == id })
                    ?? libraryViewModel?.resumeShows.first(where: { $0.id == id })
                    ?? libraryViewModel?.episodes.first(where: { $0.id == id })
                    ?? libraryViewModel?.tvShows.first(where: { $0.id == id })
                    ?? ci
            }
            guard let nextItem = resolvedCollectionItems.nextPlayableItem(fromBeginning: fromBeginning) else {
                return nil
            }
            if nextItem.type == .series {
                if !fromBeginning, let resumeEp = libraryViewModel?.resumeShows.first(where: { $0.seriesID == nextItem.id }) {
                    return resumeEp
                }
                let matching = (libraryViewModel?.episodes ?? [])
                    .filter { $0.seriesID == nextItem.id }
                    .sorted { a, b in
                        let sA = a.parentIndexNumber ?? 1
                        let sB = b.parentIndexNumber ?? 1
                        if sA != sB { return sA < sB }
                        return (a.indexNumber ?? 1) < (b.indexNumber ?? 1)
                    }
                return matching.nextPlayableItem(fromBeginning: fromBeginning) ?? nextItem
            }
            return nextItem
        }
        return displayItem
    }

    func handleProgressUpdated(itemID: String, positionTicks: Int, totalTicks: Int?) {
        if itemID == displayItem?.id {
            if detailedItem?.id == itemID {
                detailedItem?.updateProgress(positionTicks: positionTicks, totalTicks: totalTicks)
            }
            if sourceItem?.id == itemID {
                sourceItem?.updateProgress(positionTicks: positionTicks, totalTicks: totalTicks)
            }
        }
        episodes.updateProgress(for: itemID, positionTicks: positionTicks, totalTicks: totalTicks)
        collectionItems.updateProgress(for: itemID, positionTicks: positionTicks, totalTicks: totalTicks)
    }

    func episodeThumbnailURL(for episode: BaseItemDto) -> URL? {
        guard let client, let id = episode.id else { return nil }
        let imageType = episode.imageTags?.keys.contains("Thumb") == true ? "Thumb" : "Primary"
        return client.url(with: Paths.getItemImage(
            itemID: id,
            imageType: imageType,
            parameters: .init(maxWidth: 600, quality: 90)
        ))
    }

    func castImageURL(for person: BaseItemPerson, client fallbackClient: JellyfinClient? = nil) -> URL? {
        let activeClient = client ?? fallbackClient
        guard let activeClient,
              let id = person.id,
              person.primaryImageTag != nil else { return nil }
        return activeClient.url(with: Paths.getItemImage(
            itemID: id,
            imageType: "Primary",
            parameters: .init(maxWidth: 200, quality: 80, tag: person.primaryImageTag)
        ))
    }

    func handleFavoriteNotification(itemID: String, isFavorite: Bool) {
        if displayItem?.id == itemID {
            detailedItem?.setFavorite(isFavorite)
            sourceItem?.setFavorite(isFavorite)
        }
    }

    func loadCollectionItems(client: JellyfinClient, userID: String?, libraryViewModel: LibraryViewModel? = nil) async {
        guard let collectionID = sourceItem?.id ?? detailedItem?.id else { return }
        isLoadingCollectionItems = true
        defer { isLoadingCollectionItems = false }

        var params = Paths.GetItemsParameters()
        params.userID = userID
        params.parentID = collectionID
        params.isRecursive = true
        params.isCollapseBoxSetItems = false
        params.fields = [.primaryImageAspectRatio, .genres, .tags, .overview, .mediaSources, .mediaStreams]
        params.enableUserData = userID != nil
        params.enableImages = true

        let items = (try? await client.send(Paths.getItems(parameters: params)).value.items) ?? []

        let sorted = items.sorted { a, b in
            let dateA = a.premiereDate ?? (a.productionYear.flatMap { Calendar.current.date(from: DateComponents(year: $0)) } ?? .distantPast)
            let dateB = b.premiereDate ?? (b.productionYear.flatMap { Calendar.current.date(from: DateComponents(year: $0)) } ?? .distantPast)
            if dateA != dateB {
                return dateA < dateB
            }
            return (a.sortName ?? a.name ?? "") < (b.sortName ?? b.name ?? "")
        }

        collectionItems = sorted.map { item in
            guard let id = item.id else { return item }
            return libraryViewModel?.movies.first(where: { $0.id == id })
                ?? libraryViewModel?.resumeShows.first(where: { $0.id == id })
                ?? libraryViewModel?.episodes.first(where: { $0.id == id })
                ?? libraryViewModel?.tvShows.first(where: { $0.id == id })
                ?? item
        }
        if let collectionID = sourceItem?.id ?? detailedItem?.id {
            Self.collectionItemsCache[collectionID] = collectionItems
        }
    }

    // MARK: - Playback Media Configuration Management

    var selectedMediaSource: MediaSourceInfo? {
        if let id = selectedMediaSourceID {
            return mediaSources.first(where: { $0.id == id }) ?? mediaSources.first
        }
        return mediaSources.first
    }

    var availableAudioStreams: [MediaStream] {
        guard let source = selectedMediaSource else { return [] }
        return (source.mediaStreams ?? []).filter { $0.type == .audio }
    }

    var availableSubtitleStreams: [MediaStream] {
        guard let source = selectedMediaSource else { return [] }
        return (source.mediaStreams ?? []).filter { $0.type == .subtitle }
    }

    var currentVideoStream: MediaStream? {
        guard let source = selectedMediaSource else { return nil }
        return (source.mediaStreams ?? []).first(where: { $0.type == .video })
    }

    static let standardBitratePresets: [Int] = [
        120_000_000,
        80_000_000,
        60_000_000,
        40_000_000,
        20_000_000,
        15_000_000,
        10_000_000,
        8_000_000,
        6_000_000,
        4_000_000,
        3_000_000,
        2_000_000,
        1_500_000,
        1_000_000,
        720_000,
        420_000
    ]

    static let fallbackBitratePresets: [Int] = [
        20_000_000,
        10_000_000,
        8_000_000,
        6_000_000,
        4_000_000,
        3_000_000,
        2_000_000,
        1_500_000,
        1_000_000,
        720_000,
        420_000
    ]

    func formatBitrate(_ bps: Int) -> String {
        guard bps > 0 else { return "0 bps" }
        if bps >= 1_000_000 {
            let mbps = Double(bps) / 1_000_000.0
            if mbps >= 10 {
                return String(format: "%.0f Mbps", mbps)
            } else if mbps.truncatingRemainder(dividingBy: 1) == 0 {
                return String(format: "%.0f Mbps", mbps)
            } else {
                return String(format: "%.1f Mbps", mbps)
            }
        } else {
            let kbps = Int(round(Double(bps) / 1_000.0))
            return "\(kbps) Kbps"
        }
    }

    var currentBitrate: Int? {
        if let b = selectedMediaSource?.bitrate, b > 0 { return b }
        if let b = currentVideoStream?.bitRate, b > 0 { return b }
        return nil
    }

    var availableQualities: [QualityOption] {
        var options: [QualityOption] = []

        if mediaSources.count > 1 {
            for source in mediaSources {
                let sBitrate = (source.bitrate.flatMap { $0 > 0 ? $0 : nil })
                    ?? (source.mediaStreams ?? []).first(where: { $0.type == .video })?.bitRate.flatMap { $0 > 0 ? $0 : nil }
                let bitText = sBitrate.map { " (\(formatBitrate($0)))" } ?? ""
                let name: String
                if let sName = source.name, !sName.isEmpty {
                    name = "\(sName)\(bitText)"
                } else if sBitrate != nil {
                    name = "Original\(bitText)"
                } else {
                    name = "Version"
                }
                options.append(QualityOption(
                    id: source.id ?? UUID().uuidString,
                    label: name,
                    mediaSourceID: source.id,
                    maxBitrate: nil
                ))
            }
        } else {
            let origLabel: String
            if let origBitrate = currentBitrate {
                origLabel = "Original (\(formatBitrate(origBitrate)))"
            } else {
                origLabel = "Auto (Original)"
            }
            options.append(QualityOption(
                id: "orig",
                label: origLabel,
                mediaSourceID: selectedMediaSourceID,
                maxBitrate: nil
            ))
        }

        let presetsToShow: [Int]
        if let origBitrate = currentBitrate {
            let threshold = Int(Double(origBitrate) * 0.9)
            presetsToShow = Self.standardBitratePresets.filter { $0 <= threshold }
        } else {
            presetsToShow = Self.fallbackBitratePresets
        }

        for preset in presetsToShow {
            let label = formatBitrate(preset)
            options.append(QualityOption(
                id: "bitrate-\(preset)",
                label: label,
                mediaSourceID: selectedMediaSourceID,
                maxBitrate: preset
            ))
        }

        return options
    }

    var selectedQualityLabel: String {
        if let maxBitrate = selectedMaxBitrate {
            return formatBitrate(maxBitrate)
        }
        if mediaSources.count > 1, let source = selectedMediaSource {
            let sBitrate = (source.bitrate.flatMap { $0 > 0 ? $0 : nil })
                ?? currentVideoStream?.bitRate.flatMap { $0 > 0 ? $0 : nil }
            let bitText = sBitrate.map { " (\(formatBitrate($0)))" } ?? ""
            if let sName = source.name, !sName.isEmpty {
                return "\(sName)\(bitText)"
            }
            return sBitrate.map { "Original (\(formatBitrate($0)))" } ?? "Original"
        }
        if let origBitrate = currentBitrate {
            return "Original (\(formatBitrate(origBitrate)))"
        }
        return "Auto"
    }

    func isQualitySelected(_ option: QualityOption) -> Bool {
        if let maxBitrate = option.maxBitrate {
            return selectedMaxBitrate == maxBitrate
        }
        if selectedMaxBitrate != nil {
            return false
        }
        if let sourceID = option.mediaSourceID {
            return selectedMediaSourceID == sourceID
        }
        return true
    }

    func selectQuality(_ option: QualityOption) {
        if let sourceID = option.mediaSourceID {
            selectMediaSource(sourceID)
        }
        selectedMaxBitrate = option.maxBitrate
    }

    func audioStreamLabel(for stream: MediaStream) -> String {
        let language = stream.localizedLanguage ?? stream.language ?? stream.displayTitle ?? "Audio"
        if let title = stream.title, !title.isEmpty {
            let lower = title.lowercased()
            let isCodecOnly = ["aac", "ac3", "eac3", "dts", "truehd", "flac", "mp3", "opus", "stereo", "5.1", "7.1"].contains { lower == $0 || lower == "\($0) 5.1" || lower == "\($0) stereo" }
            if !isCodecOnly && !lower.contains(language.lowercased()) {
                return "\(language) (\(title))"
            }
        }

        let matching = availableAudioStreams.filter { ($0.localizedLanguage ?? $0.language ?? $0.displayTitle ?? "Audio") == language }
        if matching.count > 1, let index = matching.firstIndex(where: { $0.index == stream.index }) {
            return "\(language) (\(index + 1))"
        }
        return language
    }

    var selectedAudioStreamLabel: String {
        guard let stream = availableAudioStreams.first(where: { $0.index == selectedAudioStreamIndex }) else {
            return "Default Audio"
        }
        return audioStreamLabel(for: stream)
    }

    func subtitleStreamLabel(for stream: MediaStream) -> String {
        let language = stream.localizedLanguage ?? stream.language ?? stream.displayTitle ?? "Subtitle"
        var suffixes: [String] = []
        if stream.isHearingImpaired == true {
            suffixes.append("SDH")
        } else if stream.isForced == true {
            suffixes.append("Forced")
        }

        if let title = stream.title, !title.isEmpty {
            let lower = title.lowercased()
            let isFormatOnly = ["srt", "ass", "subrip", "vtt", "pgs", "sub"].contains { lower == $0 }
            if !isFormatOnly && !suffixes.contains(where: { lower.contains($0.lowercased()) }) && !lower.contains(language.lowercased()) {
                suffixes.append(title)
            }
        }

        if !suffixes.isEmpty {
            return "\(language) (\(suffixes.joined(separator: ", ")))"
        }

        let matching = availableSubtitleStreams.filter { ($0.localizedLanguage ?? $0.language ?? $0.displayTitle ?? "Subtitle") == language }
        if matching.count > 1, let index = matching.firstIndex(where: { $0.index == stream.index }) {
            return "\(language) (\(index + 1))"
        }
        return language
    }

    var selectedSubtitleStreamLabel: String {
        if selectedSubtitleStreamIndex == nil || selectedSubtitleStreamIndex == -1 {
            return "Off"
        }
        guard let stream = availableSubtitleStreams.first(where: { $0.index == selectedSubtitleStreamIndex }) else {
            return "Off"
        }
        return subtitleStreamLabel(for: stream)
    }

    func loadPlaybackOptions(for item: BaseItemDto, client: JellyfinClient?, userID: String?) async {
        if let itemSources = item.mediaSources, !itemSources.isEmpty {
            self.mediaSources = itemSources
            configureInitialStreamSelection()
        }

        guard let client, let itemID = item.id else { return }

        if mediaSources.isEmpty {
            isLoadingPlaybackOptions = true
        }

        do {
            let response = try await client.send(Paths.getPlaybackInfo(itemID: itemID, userID: userID)).value
            if let sources = response.mediaSources, !sources.isEmpty {
                self.mediaSources = sources
                configureInitialStreamSelection()
            }
        } catch {
            AppLogger.warning("Failed to fetch playback info: \(error.localizedDescription)", tag: "MediaDetailViewModel")
        }

        isLoadingPlaybackOptions = false
    }

    private func configureInitialStreamSelection() {
        if selectedMediaSourceID == nil || !mediaSources.contains(where: { $0.id == selectedMediaSourceID }) {
            selectedMediaSourceID = mediaSources.first?.id
        }

        guard let source = selectedMediaSource else { return }

        let audios = (source.mediaStreams ?? []).filter { $0.type == .audio }
        if selectedAudioStreamIndex == nil || !audios.contains(where: { $0.index == selectedAudioStreamIndex }) {
            selectedAudioStreamIndex = source.defaultAudioStreamIndex
                ?? audios.first(where: { $0.isDefault == true })?.index
                ?? audios.first?.index
        }

        let subs = (source.mediaStreams ?? []).filter { $0.type == .subtitle }
        if selectedSubtitleStreamIndex == nil {
            if let defSub = source.defaultSubtitleStreamIndex, subs.contains(where: { $0.index == defSub }) {
                selectedSubtitleStreamIndex = defSub
            } else {
                selectedSubtitleStreamIndex = -1
            }
        }
    }

    func selectMediaSource(_ sourceID: String?) {
        guard selectedMediaSourceID != sourceID else { return }
        selectedMediaSourceID = sourceID
        selectedMaxBitrate = nil
        guard let source = selectedMediaSource else { return }

        let audios = (source.mediaStreams ?? []).filter { $0.type == .audio }
        selectedAudioStreamIndex = source.defaultAudioStreamIndex
            ?? audios.first(where: { $0.isDefault == true })?.index
            ?? audios.first?.index

        let subs = (source.mediaStreams ?? []).filter { $0.type == .subtitle }
        if let defSub = source.defaultSubtitleStreamIndex, subs.contains(where: { $0.index == defSub }) {
            selectedSubtitleStreamIndex = defSub
        } else {
            selectedSubtitleStreamIndex = -1
        }
    }

    func selectAudioStream(index: Int?) {
        selectedAudioStreamIndex = index
    }

    func selectSubtitleStream(index: Int?) {
        selectedSubtitleStreamIndex = index
    }

    func resetToDefaults() {
        selectedMaxBitrate = nil
        selectedMediaSourceID = mediaSources.first?.id
        guard let source = selectedMediaSource else {
            selectedAudioStreamIndex = nil
            selectedSubtitleStreamIndex = -1
            return
        }

        let audios = (source.mediaStreams ?? []).filter { $0.type == .audio }
        selectedAudioStreamIndex = source.defaultAudioStreamIndex
            ?? audios.first(where: { $0.isDefault == true })?.index
            ?? audios.first?.index

        let subs = (source.mediaStreams ?? []).filter { $0.type == .subtitle }
        if let defSub = source.defaultSubtitleStreamIndex, subs.contains(where: { $0.index == defSub }) {
            selectedSubtitleStreamIndex = defSub
        } else {
            selectedSubtitleStreamIndex = -1
        }
    }

}
