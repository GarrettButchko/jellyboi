//
//  MediaDetailViewModel.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 9/2/26.
//

import Foundation
import CoreGraphics
import Observation
import Get
import JellyfinAPI
import LoggingKit

@Observable
@MainActor
class MediaDetailViewModel {

    // MARK: - State

    var detailedItem: BaseItemDto?
    var sourceItem: BaseItemDto?
    var seriesItem: BaseItemDto?
    var similarItems: LoadingState<BaseItemDto> = .empty
    var specialFeatures: LoadingState<BaseItemDto> = .empty
    var seasons: [BaseItemDto] = []
    var episodes: LoadingState<BaseItemDto> = .empty
    var collectionItems: LoadingState<BaseItemDto> = .empty
    var selectedSeasonIndex: Int = 0
    var scrolledEpisodeID: String?
    var hasInitialEpisodeScrolled: Bool = false
    var heroAspectRatio: CGFloat = 2.0 / 3.0
    var hasDetectedBitmapRatio = false
    var heroReady = false
    var isLoading = false

    var isLoadingCollectionItems: Bool { collectionItems.isLoading }
    var isLoadingEpisodes: Bool { episodes.isLoading }
    var isLoadingSpecialFeatures: Bool { specialFeatures.isLoading }
    var isLoadingSimilarItems: Bool { similarItems.isLoading }

    var client: JellyfinClient?
    weak var libraryViewModel: LibraryViewModel?
    static var collectionItemsCache: [String: [BaseItemDto]] = [:]
    static var seasonsCache: [String: [BaseItemDto]] = [:]
    static var episodesCache: [String: [BaseItemDto]] = [:]

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
                self.collectionItems = cached.isEmpty ? .empty : .full(cached)
            }
            if item.type == .series, let id = item.id {
                if let cachedSeasons = Self.seasonsCache[id] {
                    self.seasons = cachedSeasons
                }
                if let cachedEpisodes = Self.episodesCache[id], !cachedEpisodes.isEmpty {
                    self.episodes = .full(cachedEpisodes)
                }
                if self.seasons.isEmpty && !self.episodes.isEmpty {
                    self.seasons = Self.deriveSeasons(from: self.episodes.elements, seriesID: id)
                }
            }
            if item.type == .series && self.episodes.isEmpty {
                self.episodes = .loading
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
            return collectionItems.isLoading || collectionItems.isEmpty
        }
        return false
    }

    var isPlayDisabled: Bool {
        guard let currentItem = displayItem else { return false }
        if currentItem.type == .boxSet {
            return collectionItems.isLoading || collectionItems.isEmpty
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
                self.specialFeatures = cached.isEmpty ? .empty : .full(cached)
            } else {
                self.specialFeatures = .loading
            }
            if let cachedSimilar = lvm.cachedSimilarItems(for: id) {
                self.similarItems = cachedSimilar.isEmpty ? .empty : .full(cachedSimilar)
            } else {
                self.similarItems = .loading
            }
        } else {
            self.specialFeatures = .loading
            self.similarItems = .loading
        }

        if item.type == .series {
            if let seriesID = item.id {
                if let cached = Self.episodesCache[seriesID], !cached.isEmpty && self.episodes.isEmpty {
                    self.episodes = .full(cached)
                } else if let lvm = libraryViewModel {
                    let cached = lvm.episodes(forSeriesID: seriesID)
                    if !cached.isEmpty && self.episodes.isEmpty {
                        self.episodes = .full(cached)
                    }
                }
                if let cached = Self.seasonsCache[seriesID], !cached.isEmpty && self.seasons.isEmpty {
                    self.seasons = cached
                }
                if self.seasons.isEmpty && !self.episodes.isEmpty {
                    self.seasons = Self.deriveSeasons(from: self.episodes.elements, seriesID: seriesID)
                }
            }
            if self.episodes.isEmpty {
                self.episodes = .loading
            }
        }

        if item.type == .boxSet, let collectionID = item.id {
            if let cached = Self.collectionItemsCache[collectionID], !cached.isEmpty && self.collectionItems.isEmpty {
                self.collectionItems = .full(cached)
            } else if self.collectionItems.isEmpty {
                self.collectionItems = .loading
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
                self.episodes = downloadedEps.isEmpty ? .empty : .full(downloadedEps)
                let seasonNumbers = Set(downloadedEps.compactMap(\.parentIndexNumber))
                self.seasons = seasonNumbers.sorted().map { sNum in
                    BaseItemDto(id: "\(itemID)-season-\(sNum)", indexNumber: sNum, name: "Season \(sNum)", type: .season)
                }
            } else if episodes.isLoading {
                episodes = .empty
            }
            if specialFeatures.isLoading {
                specialFeatures = .empty
            }
            if similarItems.isLoading {
                similarItems = .empty
            }
            return
        }

        let isSeries = item.type == .series || resolvedItem.type == .series
        let isBoxSet = item.type == .boxSet || resolvedItem.type == .boxSet
        let isEpisode = item.type == .episode || resolvedItem.type == .episode

        // STAGE 1 & 2 in parallel: Fetch essential details and series/seasons concurrently
        async let detailFetch = client.fetchItemOrNil(itemID: itemID, userID: userID)
        async let seriesOrCollectionTask: Void = { @MainActor in
            if isSeries {
                await loadSeasonsAndEpisodes(client: client, userID: userID)
            } else {
                episodes = .empty
                if isBoxSet {
                    await loadCollectionItems(client: client, userID: userID, libraryViewModel: libraryViewModel)
                } else if isEpisode {
                    await loadParentSeries(client: client, userID: userID, libraryViewModel: libraryViewModel)
                }
            }
        }()

        let detailResult = await detailFetch
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

        _ = await seriesOrCollectionTask

        // STAGE 3: Secondary below-the-fold content (Similar items & Special features)
        guard !Task.isCancelled else { return }
        let similar = await libraryViewModel.similarItems(for: itemID, client: client, userID: userID)
        similarItems = similar.isEmpty ? .empty : .full(similar)

        guard !Task.isCancelled else { return }
        let features = await libraryViewModel.specialFeatures(for: itemID, client: client, userID: userID)
        specialFeatures = features.isEmpty ? .empty : .full(features)
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
