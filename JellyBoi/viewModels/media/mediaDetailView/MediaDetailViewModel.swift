//
//  MediaDetailViewModel.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 8/19/26.
//

import SwiftUI
import SDWebImageSwiftUI
import JellyfinAPI

// MARK: - MediaDetailViewModel

@MainActor
@Observable
class MediaDetailViewModel {

    // MARK: - State

    var detailedItem: BaseItemDto?
    var sourceItem: BaseItemDto?
    var seriesItem: BaseItemDto?

    // MARK: - Consolidated Loading Status Enums

    /// Single source of truth for the primary metadata of this screen: `.loading` from the moment
    /// the screen is created until the details resolve (fetched, reused, or served offline).
    var primaryDetailsStatus: DetailSectionStatus = .idle
    var episodesStatus: DetailSectionStatus = .idle
    var collectionStatus: DetailSectionStatus = .idle
    var secondaryStatus: DetailSectionStatus = .idle
    
    var collectionItems: [BaseItemDto] = []
    var episodes: [BaseItemDto] = []
    var cast: [BaseItemPerson] = []
    var specialFeatures: [BaseItemDto] = []
    var similarItems: [BaseItemDto] = []
    var seasons: [BaseItemDto] = []
    
    var selectedSeasonIndex: Int = 0
    var scrolledEpisodeID: String?
    
    var hasInitialEpisodeScrolled: Bool = false
    var heroAspectRatio: CGFloat = MediaAspectRatio.poster
    var hasDetectedBitmapRatio = false
    var mediaSources: [MediaSourceInfo] = []
    var selectedMediaSourceID: String?
    var selectedAudioStreamIndex: Int?
    var selectedSubtitleStreamIndex: Int? = -1

    /// True once the item details for this screen have been resolved (fetched, reused, or served
    /// offline). The base item handed to the screen only carries a partial copy of the metadata,
    /// so sections that depend on the full item wait for this before rendering real content.
    var hasResolvedItemDetails: Bool {
        primaryDetailsStatus.isLoaded || primaryDetailsStatus.isEmpty
    }

    // MARK: - Shared Static Cache
    static var seasonsCache: [String: [BaseItemDto]] = [:]
    static var episodesCache: [String: [BaseItemDto]] = [:]
    static var collectionItemsCache: [String: [BaseItemDto]] = [:]

    // MARK: - Dependencies (set in load)

    weak var client: JellyfinClient?
    weak var libraryViewModel: LibraryViewModel?
    weak var playbackManager: PlaybackManager?
    weak var serverViewModel: ServerViewModel?

    // MARK: - Server User Data

    /// Applies server-reported user data so this screen never keeps its own idea of watch state.
    @ObservationIgnored
    private var userDataTask: Task<Void, Never>?

    // MARK: - Playback Options Sheet State
    var selectedMaxBitrate: Int?
    var isLoadingPlaybackOptions = false

    // MARK: - Alert State
    var seriesAlertAction: SeriesConfirmationAlert?
    var downloadAlertAction: DownloadAlertAction?

    // MARK: - Initialization

    init(item: BaseItemDto? = nil) {
        if let item {
            self.sourceItem = item
            let actors = (item.people ?? []).filter { $0.type == .actor }
            self.cast = (item.type != .boxSet) ? actors : []

            // Primary Details Status
            self.primaryDetailsStatus = .loading

            if item.type == .boxSet {
                if let id = item.id, let cached = Self.collectionItemsCache[id] {
                    self.collectionItems = cached
                    self.collectionStatus = cached.isEmpty ? .empty : .loaded
                } else {
                    self.collectionItems = []
                    self.collectionStatus = .loading
                }
            } else {
                self.collectionItems = []
                self.collectionStatus = .empty
            }

            if item.type == .series, let id = item.id {
                if let cachedSeasons = Self.seasonsCache[id] {
                    self.seasons = cachedSeasons
                }
                if let cachedEpisodes = Self.episodesCache[id], !cachedEpisodes.isEmpty {
                    self.episodes = cachedEpisodes
                    self.episodesStatus = .loaded
                }
                if self.seasons.isEmpty && !self.episodes.isEmpty {
                    self.seasons = Self.deriveSeasons(from: self.episodes, seriesID: id)
                }
            }
            if item.type == .series && self.episodes.isEmpty {
                self.episodes = []
                self.episodesStatus = .loading
            } else if item.type != .series {
                self.episodes = []
                self.episodesStatus = .empty
            }

            if item.type != .boxSet && item.type != .episode {
                self.similarItems = []
                self.specialFeatures = []
                self.secondaryStatus = .loading
            } else {
                self.similarItems = []
                self.specialFeatures = []
                self.secondaryStatus = .empty
            }

            if let ratio = item.primaryImageAspectRatio, ratio > 0 {
                self.heroAspectRatio = CGFloat(ratio)
            } else if item.type == .episode {
                self.heroAspectRatio = MediaAspectRatio.thumbnail
            }
            if let sources = item.mediaSources, !sources.isEmpty {
                self.mediaSources = sources
                configureInitialStreamSelection()
            }
        }

        userDataTask = Task { @MainActor [weak self] in
            for await notification in NotificationCenter.default.notifications(named: .mediaUserDataChanged) {
                guard let self else { break }
                guard let dtos = notification.userInfo?["userData"] as? [UserItemDataDto] else { continue }
                self.applyUserData(dtos)
            }
        }
    }

    deinit {
        userDataTask?.cancel()
    }

    /// Writes server-reported user data into every item this screen is holding.
    ///
    /// Reset, favorite, and progress changes all arrive from the server, so nothing here infers
    /// watch state locally.
    func applyUserData(_ dtos: [UserItemDataDto]) {
        for dto in dtos {
            let itemID = dto.itemID ?? dto.key

            if detailedItem?.id == itemID {
                detailedItem?.userData = dto
            }
            if sourceItem?.id == itemID {
                sourceItem?.userData = dto
            }
            if let index = episodes.firstIndex(where: { $0.id == itemID }) {
                episodes[index].userData = dto
            }
            if let index = collectionItems.firstIndex(where: { $0.id == itemID }) {
                collectionItems[index].userData = dto
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
            return collectionStatus.isLoading || collectionItems.isEmpty
        }
        return false
    }

    var isPlayDisabled: Bool {
        guard let currentItem = displayItem else { return false }
        if currentItem.type == .boxSet {
            return collectionStatus.isLoading || collectionItems.isEmpty
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

    func episodeSeasonTitle(libraryViewModel: LibraryViewModel?) -> String? {
        guard let item = displayItem, item.type == .episode else { return nil }
        if let seasonName = item.seasonName, !seasonName.isEmpty {
            return seasonName
        }
        if let seasonNum = item.parentIndexNumber {
            return "Season \(seasonNum)"
        }
        if let seriesID = item.seriesID,
           let show = libraryViewModel?.tvShows.first(where: { $0.id == seriesID }) {
            return show.name
        }
        return nil
    }

    var isPlayed: Bool {
        get {
            displayItem?.userData?.isPlayed ?? false
        }
        set {
            if detailedItem != nil {
                detailedItem?.userData?.isPlayed = newValue
            }
            if sourceItem != nil {
                sourceItem?.userData?.isPlayed = newValue
            }
        }
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

    func toggleFavorite() {
        guard let itemID = displayItem?.id else { return }
        let isFavorite = !(displayItem?.isFavorite ?? false)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            detailedItem?.setFavorite(isFavorite)
            sourceItem?.setFavorite(isFavorite)
        }
        Task {
            _ = await serverViewModel?.setFavorite(isFavorite, forItemID: itemID)
        }
    }

    // MARK: - Debug Visibility Flags

    #if DEBUG
    var isOverviewHidden: Bool { DebugSettings.shared.hideOverview }
    var isCastHidden: Bool { DebugSettings.shared.hideCastAndCrew }
    var isEpisodesHidden: Bool { DebugSettings.shared.hideEpisodes }
    var areTagsHidden: Bool { DebugSettings.shared.hideTags }
    var areSimilarItemsHidden: Bool { DebugSettings.shared.hideSimilarItems }
    var isSpecialFeaturesHidden: Bool { DebugSettings.shared.hideSpecialFeatures }
    #else
    var isOverviewHidden: Bool { false }
    var isCastHidden: Bool { false }
    var isEpisodesHidden: Bool { false }
    var areTagsHidden: Bool { false }
    var areSimilarItemsHidden: Bool { false }
    var isSpecialFeaturesHidden: Bool { false }
    #endif

    // MARK: - Images & Aspect Ratio

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

    func detectBitmapAspectRatio(from image: UIImage) {
        guard !hasDetectedBitmapRatio, image.size.height > 0 else { return }
        hasDetectedBitmapRatio = true
        let bitmapRatio = image.size.width / image.size.height
        if abs(heroAspectRatio - bitmapRatio) > 0.05 {
            heroAspectRatio = bitmapRatio
        }
    }

    // MARK: - Lifecycle Preparation

    func prepare(item: BaseItemDto, client: JellyfinClient?, libraryViewModel: LibraryViewModel? = nil) {
        self.sourceItem = item
        self.client = client
        self.libraryViewModel = libraryViewModel
        self.hasInitialEpisodeScrolled = false
        self.scrolledEpisodeID = nil

        let actors = (item.people ?? []).filter { $0.type == .actor }
        self.cast = (item.type != .boxSet) ? actors : []

        self.primaryDetailsStatus = .loading

        if item.type != .boxSet && item.type != .episode {
            let hasCachedFeatures = item.id.flatMap { libraryViewModel?.cachedSpecialFeatures(for: $0) }
            let hasCachedSimilar = item.id.flatMap { libraryViewModel?.cachedSimilarItems(for: $0) }

            if item.specialFeatureCount == 0 {
                self.specialFeatures = []
            } else if let cached = hasCachedFeatures {
                self.specialFeatures = cached
            } else {
                self.specialFeatures = []
            }

            if let cachedSimilar = hasCachedSimilar {
                self.similarItems = cachedSimilar
            } else {
                self.similarItems = []
            }

            if hasCachedFeatures != nil || hasCachedSimilar != nil {
                self.secondaryStatus = .loaded
            } else {
                self.secondaryStatus = .loading
            }
        } else {
            self.specialFeatures = []
            self.similarItems = []
            self.secondaryStatus = .empty
        }

        if item.type == .series {
            if let seriesID = item.id {
                if let cached = Self.episodesCache[seriesID], !cached.isEmpty && self.episodes.isEmpty {
                    self.episodes = cached
                    self.episodesStatus = .loaded
                } else if let lvm = libraryViewModel {
                    let cached = lvm.episodes(forSeriesID: seriesID)
                    if !cached.isEmpty && self.episodes.isEmpty {
                        self.episodes = cached
                        self.episodesStatus = .loaded
                    }
                }
                if let cached = Self.seasonsCache[seriesID], !cached.isEmpty && self.seasons.isEmpty {
                    self.seasons = cached
                }
                if self.seasons.isEmpty && !self.episodes.isEmpty {
                    self.seasons = Self.deriveSeasons(from: self.episodes, seriesID: seriesID)
                }
            }
            if self.episodes.isEmpty {
                self.episodes = []
                self.episodesStatus = .loading
            }
        } else {
            self.episodes = []
            self.episodesStatus = .empty
        }

        if item.type == .boxSet, let collectionID = item.id {
            if let cached = Self.collectionItemsCache[collectionID], !cached.isEmpty && self.collectionItems.isEmpty {
                self.collectionItems = cached
                self.collectionStatus = .loaded
            } else if self.collectionItems.isEmpty {
                self.collectionItems = []
                self.collectionStatus = .loading
            }
        } else {
            self.collectionItems = []
            self.collectionStatus = .empty
        }

        if let ratio = item.primaryImageAspectRatio, ratio > 0 {
            self.heroAspectRatio = CGFloat(ratio)
        } else if item.type == .episode {
            self.heroAspectRatio = MediaAspectRatio.thumbnail
        }

        if let sources = item.mediaSources, !sources.isEmpty {
            self.mediaSources = sources
            configureInitialStreamSelection()
        }
    }

    // MARK: - Loading Orchestrator

    func load(
        item: BaseItemDto,
        client: JellyfinClient,
        userID: String?,
        libraryViewModel: LibraryViewModel,
        playbackManager: PlaybackManager? = nil,
        serverViewModel: ServerViewModel? = nil
    ) async {
        self.client = client
        self.libraryViewModel = libraryViewModel
        self.playbackManager = playbackManager
        self.serverViewModel = serverViewModel

        let itemID = item.id ?? ""
        let resolvedItem = libraryViewModel.movies.first(where: { $0.id == itemID })
            ?? libraryViewModel.tvShows.first(where: { $0.id == itemID })
            ?? item
        self.sourceItem = resolvedItem
        self.hasInitialEpisodeScrolled = false
        self.scrolledEpisodeID = nil

        if !NetworkMonitor.shared.isConnected {
            withAnimation(.skeleton) {
                self.detailedItem = resolvedItem
                self.primaryDetailsStatus = .loaded
                if let sources = detailedItem?.mediaSources ?? sourceItem?.mediaSources, !sources.isEmpty {
                    self.mediaSources = sources
                    configureInitialStreamSelection()
                }
                let actors = (resolvedItem.people ?? []).filter { $0.type == .actor }
                self.cast = actors
                if item.type == .series || resolvedItem.type == .series {
                    let downloadedEps = DownloadManager.shared.downloadedEpisodes
                        .filter { ($0.seriesID ?? $0.parentBackdropItemID) == itemID }
                        .sorted { ($0.indexNumber ?? 0) < ($1.indexNumber ?? 0) }
                    self.episodes = downloadedEps
                    self.episodesStatus = downloadedEps.isEmpty ? .empty : .loaded
                    let seasonNumbers = Set(downloadedEps.compactMap(\.parentIndexNumber))
                    self.seasons = seasonNumbers.sorted().map { sNum in
                        BaseItemDto(id: "\(itemID)-season-\(sNum)", indexNumber: sNum, name: "Season \(sNum)", type: .season)
                    }
                } else {
                    episodes = []
                    episodesStatus = .empty
                }
                specialFeatures = []
                similarItems = []
                self.secondaryStatus = .empty
                collectionItems = []
                collectionStatus = .empty
            }
            if let playbackManager, let serverViewModel {
                startPreload(
                    playbackManager: playbackManager,
                    serverViewModel: serverViewModel,
                    libraryViewModel: libraryViewModel
                )
            }
            return
        }

        let isSeries = item.type == .series || resolvedItem.type == .series
        let isBoxSet = item.type == .boxSet || resolvedItem.type == .boxSet
        let isEpisode = item.type == .episode || resolvedItem.type == .episode

        // Check if primary details are already fully shown (actors and synopsis present)
        let resolvedActors = (resolvedItem.people ?? []).filter { $0.type == .actor }
        let hasCompletePrimaryData = !resolvedActors.isEmpty && !(resolvedItem.overview ?? "").isEmpty
        let shouldFetchPrimaryDetails = !hasCompletePrimaryData

        // STAGE 1 & 2 in parallel: Fetch essential details and series/seasons concurrently
        async let detailFetch: BaseItemDto? = {
            if shouldFetchPrimaryDetails {
                return await client.fetchItemOrNil(itemID: itemID, userID: userID)
            } else {
                return nil
            }
        }()

        async let seriesOrCollectionTask: Void = { @MainActor in
            if isSeries {
                // If episodes are already loaded from cache, don't re-fetch
                if episodesStatus != .loaded {
                    await loadSeasonsAndEpisodes(client: client, userID: userID)
                }
            } else {
                episodes = []
                episodesStatus = .empty
                if isBoxSet {
                    if collectionStatus != .loaded {
                        await loadCollectionItems(client: client, userID: userID, libraryViewModel: libraryViewModel)
                    }
                } else if isEpisode {
                    await loadParentSeries(client: client, userID: userID, libraryViewModel: libraryViewModel)
                }
            }
        }()

        let detailResult = await detailFetch
        guard !Task.isCancelled else { return }

        withAnimation(.skeleton) {
            if let detailResult {
                self.detailedItem = detailResult
                self.primaryDetailsStatus = .loaded

                if !isBoxSet {
                    let actors = (detailResult.people ?? sourceItem?.people ?? []).filter { $0.type == .actor }
                    self.cast = actors
                } else {
                    self.cast = []
                }

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
            } else {
                // Keep existing resolved data if network returned nil or was skipped
                let actors = (resolvedItem.people ?? []).filter { $0.type == .actor }
                self.cast = actors
                self.primaryDetailsStatus = .loaded
            }
        }

        _ = await seriesOrCollectionTask
        guard !Task.isCancelled else { return }

        if let playbackManager, let serverViewModel {
            startPreload(
                playbackManager: playbackManager,
                serverViewModel: serverViewModel,
                libraryViewModel: libraryViewModel
            )
        }

        // STAGE 3: Secondary below-the-fold content (Similar items & Special features)
        guard !Task.isCancelled else { return }
        if !isBoxSet && !isEpisode {
            // Check cache first to avoid firing secondary requests if already cached
            let cachedSimilar = libraryViewModel.cachedSimilarItems(for: itemID)
            let cachedFeatures = libraryViewModel.cachedSpecialFeatures(for: itemID)

            if let cachedSimilar, let cachedFeatures {
                withAnimation(.skeleton) {
                    similarItems = cachedSimilar
                    specialFeatures = cachedFeatures
                    secondaryStatus = (cachedSimilar.isEmpty && cachedFeatures.isEmpty) ? .empty : .loaded
                }
            } else {
                let specialCount = detailedItem?.specialFeatureCount ?? sourceItem?.specialFeatureCount
                async let similarFetch = libraryViewModel.similarItems(for: itemID, client: client, userID: userID)
                async let featuresFetch: [BaseItemDto] = specialCount == 0
                    ? []
                    : libraryViewModel.specialFeatures(for: itemID, client: client, userID: userID)

                let (similar, features) = await (similarFetch, featuresFetch)
                guard !Task.isCancelled else { return }

                withAnimation(.skeleton) {
                    similarItems = similar
                    specialFeatures = features
                    secondaryStatus = (similar.isEmpty && features.isEmpty) ? .empty : .loaded
                }
            }
        } else {
            withAnimation(.skeleton) {
                similarItems = []
                specialFeatures = []
                secondaryStatus = .empty
            }
        }
    }

    // MARK: - Parent Series

    func loadParentSeries(client: JellyfinClient, userID: String?, libraryViewModel: LibraryViewModel? = nil) async {
        guard let seriesID = sourceItem?.seriesID else { return }
        if let found = libraryViewModel?.tvShows.first(where: { $0.id == seriesID }) {
            self.seriesItem = found
            return
        }
        let fetched = await client.fetchItemOrNil(itemID: seriesID, userID: userID)
        guard !Task.isCancelled else { return }
        self.seriesItem = fetched
    }
}
