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
    var specialFeatures: [BaseItemDto] = []
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
    var isLoadingSpecialFeatures = false
    var client: JellyfinClient?
    weak var libraryViewModel: LibraryViewModel?
    static var collectionItemsCache: [String: [BaseItemDto]] = [:]

    // MARK: - Playback Configuration State

    var mediaSources: [MediaSourceInfo] = []
    var selectedMediaSourceID: String?
    var selectedMaxBitrate: Int?
    var selectedAudioStreamIndex: Int?
    var selectedSubtitleStreamIndex: Int? = -1
    var isLoadingPlaybackOptions = false

    // MARK: - Alert State

    var seriesAlertAction: SeriesConfirmationAlert?
    var downloadAlertAction: DownloadAlertAction?

    // MARK: - Initialization

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

    // MARK: - Item Presentation

    var displayItem: BaseItemDto? {
        detailedItem ?? sourceItem
    }

    var shouldShowOptionsButton: Bool {
        guard let currentItem = displayItem else { return true }
        return currentItem.type != .boxSet && currentItem.type != .series
    }

    var isOptionsDisabled: Bool {
        guard let currentItem = displayItem else { return false }
        if currentItem.type == .boxSet {
            return isLoadingCollectionItems || collectionItems.isEmpty
        }
        return false
    }

    var isPlayDisabled: Bool {
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

    // MARK: - Favorites

    var isFavorite: Bool {
        displayItem?.isFavorite ?? false
    }

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

    func handleFavoriteToggled(itemID: String, isFavorite: Bool) {
        if displayItem?.id == itemID {
            detailedItem?.setFavorite(isFavorite)
            sourceItem?.setFavorite(isFavorite)
        }
    }

    func handleFavoriteNotification(itemID: String, isFavorite: Bool) {
        if displayItem?.id == itemID {
            detailedItem?.setFavorite(isFavorite)
            sourceItem?.setFavorite(isFavorite)
        }
    }

    // MARK: - Debug Visibility Flags

    #if DEBUG
    var isOverviewHidden: Bool { DebugSettings.shared.hideOverview }
    var isCastHidden: Bool { DebugSettings.shared.hideCastAndCrew }
    var areTagsHidden: Bool { DebugSettings.shared.hideTags }
    var areSimilarItemsHidden: Bool { DebugSettings.shared.hideSimilarItems }
    var isSpecialFeaturesHidden: Bool { DebugSettings.shared.hideSpecialFeatures }
    #else
    var isOverviewHidden: Bool { false }
    var isCastHidden: Bool { false }
    var areTagsHidden: Bool { false }
    var areSimilarItemsHidden: Bool { false }
    var isSpecialFeaturesHidden: Bool { false }
    #endif

    // MARK: - Images & Aspect Ratio

    func markHeroReady() {
        heroReady = true
    }

    func updateHeroAspectRatio(from size: CGSize) {
        guard size.height > 0 else { return }
        let ratio = size.width / size.height
        hasDetectedBitmapRatio = true
        if abs(heroAspectRatio - ratio) > 0.02 {
            heroAspectRatio = ratio
        }
    }

    // MARK: - Lifecycle & Loading

    func prepare(item: BaseItemDto, client: JellyfinClient?, libraryViewModel: LibraryViewModel? = nil) {
        self.sourceItem = item
        self.client = client
        self.libraryViewModel = libraryViewModel
        self.hasInitialEpisodeScrolled = false
        self.scrolledEpisodeID = nil
        if let id = item.id, let lvm = libraryViewModel {
            if let cached = lvm.cachedSpecialFeatures(for: id) {
                self.specialFeatures = cached
                self.isLoadingSpecialFeatures = false
            } else {
                self.specialFeatures = []
                self.isLoadingSpecialFeatures = true
            }
            if let cachedSimilar = lvm.cachedSimilarItems(for: id) {
                self.similarItems = cachedSimilar
            }
        } else {
            self.specialFeatures = []
            self.isLoadingSpecialFeatures = true
        }
        if item.type == .series {
            self.isLoadingEpisodes = true
            if let seriesID = item.id, let lvm = libraryViewModel {
                let cached = lvm.episodes(forSeriesID: seriesID)
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

    func load(item: BaseItemDto, client: JellyfinClient, userID: String?, libraryViewModel: LibraryViewModel) async {
        guard let itemID = item.id else { return }
        self.client = client
        self.libraryViewModel = libraryViewModel
        let resolvedItem = libraryViewModel.item(for: itemID)
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

        // STAGE 1: Essential item details and primary playback streams
        let detailResult = await client.fetchItemOrNil(itemID: itemID, userID: userID)
        guard !Task.isCancelled else { return }
        self.detailedItem = detailResult

        if let sources = detailedItem?.mediaSources ?? sourceItem?.mediaSources, !sources.isEmpty {
            self.mediaSources = sources
            configureInitialStreamSelection()
        }

        if !hasDetectedBitmapRatio, let ratio = detailedItem?.primaryImageAspectRatio, ratio > 0 {
            let newRatio = CGFloat(ratio)
            if abs(heroAspectRatio - newRatio) > 0.02 {
                heroAspectRatio = newRatio
            }
        }

        // STAGE 2: Episodes / Collections / Series relationship
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

        // STAGE 3: Secondary below-the-fold content (Similar items & Special features)
        guard !Task.isCancelled else { return }
        similarItems = await libraryViewModel.similarItems(for: itemID, client: client, userID: userID)
        guard !Task.isCancelled else { return }
        specialFeatures = await libraryViewModel.specialFeatures(for: itemID, client: client, userID: userID)
        isLoadingSpecialFeatures = false
    }

    // MARK: - Parent Series

    func loadParentSeries(client: JellyfinClient, userID: String?, libraryViewModel: LibraryViewModel) async {
        guard let seriesID = detailedItem?.seriesID ?? sourceItem?.seriesID else { return }
        if let local = libraryViewModel.item(for: seriesID) {
            self.seriesItem = local
            return
        }
        if let fetched = await client.fetchItemOrNil(itemID: seriesID, userID: userID) {
            self.seriesItem = fetched
        }
    }
}
