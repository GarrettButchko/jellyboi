//
//  MediaDetailViewModel.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 8/19/26.
//

import SwiftUI
import SDWebImageSwiftUI
import JellyfinAPI
import Get

// MARK: - MediaDetailViewModel

@MainActor
@Observable
class MediaDetailViewModel {

    // MARK: - State

    var itemType: ItemType = .none
    var detailedItem: BaseItemDto?
    var sourceItem: BaseItemDto?
    var sourceItemId: String?

    // MARK: - Consolidated Loading Status Enums

    /// Single source of truth for the primary metadata of this screen: `.loading` from the moment
    /// the screen is created until the details resolve (fetched, reused, or served offline).
    var collectionStatus: DetailSectionStatus = .idle
    var episodesStatus: DetailSectionStatus = .idle
    var primaryDetailsStatus: DetailSectionStatus = .idle
    var secondaryStatus: DetailSectionStatus = .idle
    
    var collectionItems: [String] = []
    var episodes: [String] = []
    var cast: [BaseItemPerson] = []
    var specialFeatures: [String] = []
    var similarItems: [String] = []
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

    // MARK: - Dependencies (Stored Once)

    let library: LibraryViewModel
    let downloadManager: DownloadManager
    let playbackManager: PlaybackManager
    weak var client: JellyfinClient?
    weak var serverViewModel: ServerViewModel?

    // MARK: - Server User Data

    /// Applies server-reported user data so this screen never keeps its own idea of watch state.
    @ObservationIgnored
    private var userDataTask: Task<Void, Never>?
    @ObservationIgnored
    private var progressUpdateTask: Task<Void, Never>?

    // MARK: - Playback Options Sheet State
    var selectedMaxBitrate: Int?
    var isLoadingPlaybackOptions = false
    var hasCustomPlaybackOptions: Bool = false

    // MARK: - Alert State
    var seriesAlertAction: SeriesConfirmationAlert?
    var downloadAlertAction: DownloadAlertAction?

    // MARK: - Initialization

    init(
        item: String,
        itemType: ItemType? = nil,
        fromDetailView: Bool = false,
        library: LibraryViewModel? = nil,
        downloadManager: DownloadManager? = nil,
        playbackManager: PlaybackManager? = nil,
        serverViewModel: ServerViewModel? = nil
    ) {
        self.library = library ?? .shared
        self.downloadManager = downloadManager ?? .shared
        self.playbackManager = playbackManager ?? .shared
        self.serverViewModel = serverViewModel
        self.sourceItemId = item
        if let item = self.library[item] {
            self.sourceItem = item
            if let itemType {
                self.itemType = itemType
            } else if item.type == .episode {
                self.itemType = fromDetailView ? .episodeWithShow : .episodeWithoutShow
            } else {
                self.itemType = .from(dtoKind: item.type)
            }
            let actors = (item.people ?? []).filter { $0.type == .actor }
            self.cast = (item.type != .boxSet) ? actors : []

            // Primary Details Status
            self.primaryDetailsStatus = .loading

            if item.type == .boxSet {
                self.collectionItems = []
                self.collectionStatus = .loading
            } else {
                self.collectionItems = []
                self.collectionStatus = .empty
            }

            if item.type == .series {
                self.episodes = []
                self.episodesStatus = .loading
            } else {
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

        progressUpdateTask = Task { @MainActor [weak self] in
            for await notification in NotificationCenter.default.notifications(named: .mediaProgressUpdated) {
                guard let self else { break }
                guard let itemID = notification.object as? String,
                      let positionTicks = notification.userInfo?["positionTicks"] as? Int else { continue }
                let totalTicks = notification.userInfo?["durationTicks"] as? Int
                self.handleProgressUpdated(itemID: itemID, positionTicks: positionTicks, totalTicks: totalTicks)
            }
        }
    }

    deinit {
        userDataTask?.cancel()
        progressUpdateTask?.cancel()
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

    var shouldShowSeriesButton: Bool {
        guard itemType == .episodeWithoutShow && displayItem?.type == .episode else { return false }
        return parentSeries != nil
    }

    var parentSeries: BaseItemDto? {
        library.parentSeriesItem(for: displayItem)
    }

    var hasExtraInfo: Bool {
        guard let item = displayItem else { return false }
        let people = item.people ?? []
        return !(item.genres ?? []).isEmpty
            || !people.filter({ $0.type == .director }).isEmpty
            || !people.filter({ $0.type == .writer }).isEmpty
            || !(item.studios ?? []).isEmpty
    }

    func episodeSeasonTitle() -> String? {
        guard let item = displayItem, item.type == .episode else { return nil }
        if let seasonName = item.seasonName, !seasonName.isEmpty {
            return seasonName
        }
        if let seasonNum = item.parentIndexNumber {
            return "Season \(seasonNum)"
        }
        if let show = parentSeries {
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

    func toggleFavorite(serverViewModel: ServerViewModel? = nil) {
        let svm = serverViewModel ?? self.serverViewModel ?? ServerViewModel.shared
        guard let itemID = displayItem?.id else { return }
        let isFavorite = !(displayItem?.isFavorite ?? false)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            detailedItem?.setFavorite(isFavorite)
            sourceItem?.setFavorite(isFavorite)
        }
        Task {
            _ = await svm.setFavorite(isFavorite, forItemID: itemID)
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

    // MARK: - Loading Orchestrator

    func load(
        item: BaseItemDto? = nil,
        client: JellyfinClient,
        userID: String?,
        serverViewModel: ServerViewModel? = nil
    ) async {
        self.client = client
        self.serverViewModel = serverViewModel

        let baseItem = item ?? sourceItem ?? BaseItemDto()
        let itemID = baseItem.id ?? (sourceItemId ?? "")
        let currentItem = library[itemID] ?? baseItem
        self.sourceItem = currentItem
        self.hasInitialEpisodeScrolled = false
        self.scrolledEpisodeID = nil
        self.hasCustomPlaybackOptions = false

        let isSeries = currentItem.type == .series
        let isBoxSet = currentItem.type == .boxSet
        let isEpisode = currentItem.type == .episode

        if !NetworkMonitor.shared.isConnected {
            withAnimation(.skeleton) {
                self.detailedItem = currentItem
                self.primaryDetailsStatus = .loaded
                self.cast = (currentItem.people ?? []).filter { $0.type == .actor }

                if let sources = currentItem.mediaSources, !sources.isEmpty {
                    self.mediaSources = sources
                    configureInitialStreamSelection()
                }

                if isSeries {
                    let downloadedEps = downloadManager.downloadedEpisodes
                        .filter { ($0.seriesID ?? $0.parentBackdropItemID) == itemID }
                        .sorted { ($0.indexNumber ?? 0) < ($1.indexNumber ?? 0) }
                    for ep in downloadedEps {
                        if let id = ep.id {
                            library[id] = ep
                        }
                    }
                    self.episodes = downloadedEps.compactMap(\.id)
                    self.episodesStatus = downloadedEps.isEmpty ? .empty : .loaded
                    let seasonNumbers = Set(downloadedEps.compactMap(\.parentIndexNumber))
                    self.seasons = seasonNumbers.sorted().map { sNum in
                        BaseItemDto(id: "\(itemID)-season-\(sNum)", indexNumber: sNum, name: "Season \(sNum)", type: .season)
                    }
                } else {
                    self.episodes = []
                    self.episodesStatus = .empty
                }

                self.specialFeatures = []
                self.similarItems = []
                self.secondaryStatus = .empty
                self.collectionItems = []
                self.collectionStatus = .empty
            }
            return
        }

        // STAGE 1 & 2 in parallel: Fetch essential details and series/collections concurrently
        let actors = (currentItem.people ?? []).filter { $0.type == .actor }
        let hasCompleteDetails = !actors.isEmpty && !(currentItem.overview ?? "").isEmpty

        async let fetchedItemTask: BaseItemDto? = {
            guard !hasCompleteDetails else { return nil }
            return await client.fetchItemOrNil(itemID: itemID, userID: userID)
        }()

        async let seriesOrCollectionTask: Void = { @MainActor in
            if isSeries {
                await loadSeasonsAndEpisodes(client: client, userID: userID)
            } else {
                self.episodes = []
                self.episodesStatus = .empty
                if isBoxSet {
                    await loadCollectionItems(client: client, userID: userID)
                } else if isEpisode {
                    await loadParentSeries(client: client, userID: userID)
                }
            }
        }()

        let fetchedItem = await fetchedItemTask
        guard !Task.isCancelled else { return }

        withAnimation(.skeleton) {
            let activeItem = fetchedItem ?? currentItem
            if let fetchedItem {
                library[itemID] = fetchedItem
                self.detailedItem = fetchedItem

                if let sources = activeItem.mediaSources, !sources.isEmpty {
                    self.mediaSources = sources
                    configureInitialStreamSelection()
                }

                if !hasDetectedBitmapRatio, let ratio = activeItem.primaryImageAspectRatio, ratio > 0 {
                    let newRatio = CGFloat(ratio)
                    if abs(heroAspectRatio - newRatio) > 0.02 {
                        heroAspectRatio = newRatio
                    }
                }
            }

            self.cast = isBoxSet ? [] : (activeItem.people ?? []).filter { $0.type == .actor }
            self.primaryDetailsStatus = .loaded
        }

        _ = await seriesOrCollectionTask
        guard !Task.isCancelled else { return }

        // STAGE 3: Secondary below-the-fold content (Similar items & Special features)
        if !isBoxSet && !isEpisode {
            let specialCount = displayItem?.specialFeatureCount ?? 0
            async let similarFetch = loadSimilarItems(itemID: itemID, client: client, userID: userID)
            async let featuresFetch: [String] = specialCount == 0
                ? []
                : loadSpecialFeatures(itemID: itemID, client: client, userID: userID)

            let (similar, features) = await (similarFetch, featuresFetch)
            guard !Task.isCancelled else { return }

            withAnimation(.skeleton) {
                self.similarItems = similar
                self.specialFeatures = features
                self.secondaryStatus = (similar.isEmpty && features.isEmpty) ? .empty : .loaded
            }
        } else {
            withAnimation(.skeleton) {
                self.similarItems = []
                self.specialFeatures = []
                self.secondaryStatus = .empty
            }
        }
    }

    // MARK: - Similar Items & Special Features

    func loadSimilarItems(itemID: String, client: JellyfinClient, userID: String?) async -> [String] {
        let result = (try? await client.send(
            Paths.getSimilarItems(
                itemID: itemID,
                parameters: .init(
                    userID: userID,
                    limit: 12,
                    fields: [.primaryImageAspectRatio]
                )
            )
        ).value.items) ?? []
        for item in result {
            if let id = item.id, library[id] == nil {
                library[id] = item
            }
        }
        return result.compactMap(\.id)
    }

    func loadSpecialFeatures(itemID: String, client: JellyfinClient, userID: String?) async -> [String] {
        let result = (try? await client.send(
            Paths.getSpecialFeatures(itemID: itemID, userID: userID)
        ).value) ?? []
        for item in result {
            if let id = item.id {
                library[id] = item
            }
        }
        return result.compactMap(\.id)
    }

    // MARK: - Parent Series

    func loadParentSeries(client: JellyfinClient, userID: String?) async {
        guard let seriesID = sourceItem?.seriesID else { return }
        if library[seriesID] != nil {
            return
        }
        if let fetched = await client.fetchItemOrNil(itemID: seriesID, userID: userID) {
            guard !Task.isCancelled else { return }
            library[seriesID] = fetched
        }
    }
}
