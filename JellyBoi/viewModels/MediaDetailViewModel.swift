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
    var heroAspectRatio: CGFloat = 2.0 / 3.0
    var hasDetectedBitmapRatio = false
    var heroReady = false
    var isLoading = false
    var isLoadingCollectionItems = false
    private var client: JellyfinClient?

    init(item: BaseItemDto? = nil) {
        if let item {
            self.sourceItem = item
            if let ratio = item.primaryImageAspectRatio, ratio > 0 {
                self.heroAspectRatio = CGFloat(ratio)
            } else if item.type == .episode {
                self.heroAspectRatio = 16.0 / 9.0
            }
        }
    }

    var displayItem: BaseItemDto? {
        detailedItem ?? sourceItem
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

    func prepare(item: BaseItemDto, client: JellyfinClient?) {
        self.sourceItem = item
        self.client = client
        if let ratio = item.primaryImageAspectRatio, ratio > 0 {
            self.heroAspectRatio = CGFloat(ratio)
        } else if item.type == .episode {
            self.heroAspectRatio = 16.0 / 9.0
        }
    }

    func clearProgress(for itemID: String) {
        if displayItem?.id == itemID || displayItem?.seriesID == itemID {
            detailedItem?.clearProgress()
            sourceItem?.clearProgress()
        }
        episodes.clearProgress(for: itemID, matchingSeries: true)
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
        self.sourceItem = item
        isLoading = true
        defer { isLoading = false }

        async let detailResult: BaseItemDto? = {
            try? await client.send(Paths.getItem(itemID: itemID, userID: userID)).value
        }()
        async let similarResult: [BaseItemDto] = libraryViewModel.similarItems(
            for: itemID, client: client, userID: userID
        )

        detailedItem = await detailResult
        similarItems = await similarResult

        if !hasDetectedBitmapRatio, let ratio = detailedItem?.primaryImageAspectRatio, ratio > 0 {
            let newRatio = CGFloat(ratio)
            if abs(heroAspectRatio - newRatio) > 0.005 {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                    heroAspectRatio = newRatio
                }
            }
        }

        if item.type == .series || detailedItem?.type == .series {
            await loadSeasonsAndEpisodes(client: client, userID: userID)
        } else if item.type == .boxSet || detailedItem?.type == .boxSet {
            await loadCollectionItems(client: client, userID: userID)
        } else if item.type == .episode || detailedItem?.type == .episode {
            await loadParentSeries(client: client, userID: userID, libraryViewModel: libraryViewModel)
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
        guard let seriesID = sourceItem?.id else { return }

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
            guard season.parentIndexNumber != 0 else { return false }
            return season.type == .season
        }
        seasons = filtered.isEmpty ? seasonResult : filtered
        guard !seasons.isEmpty else { return }

        // Load all seasons' episodes in parallel to find the in-progress one
        let allEpisodes = await withTaskGroup(of: (Int, [BaseItemDto]).self) { group in
            for (index, season) in seasons.enumerated() {
                group.addTask {
                    let eps = (try? await client.send(
                        Paths.getEpisodes(
                            seriesID: seriesID,
                            parameters: .init(
                                userID: userID,
                                fields: [.primaryImageAspectRatio, .mediaSources, .mediaStreams],
                                season: season.parentIndexNumber,
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

        // Default to the season containing an in-progress episode, else Season 1
        let inProgressIndex = allEpisodes.enumerated().first { _, eps in
            eps.contains { episode in
                guard let percent = episode.userData?.playedPercentage,
                      let isPlayed = episode.userData?.isPlayed else { return false }
                return percent > 0 && percent < 85 && !isPlayed
            }
        }?.offset ?? 0

        selectedSeasonIndex = inProgressIndex
        episodes = allEpisodes.indices.contains(selectedSeasonIndex) ? allEpisodes[selectedSeasonIndex] : []
    }

    func selectSeason(_ index: Int, client: JellyfinClient, userID: String?) async {
        guard seasons.indices.contains(index), index != selectedSeasonIndex else { return }
        episodes = []
        selectedSeasonIndex = index
        let result = (try? await client.send(
            Paths.getEpisodes(
                seriesID: sourceItem?.id ?? "",
                parameters: .init(
                    userID: userID,
                    fields: [.primaryImageAspectRatio, .mediaSources, .mediaStreams],
                    season: seasons[index].parentIndexNumber,
                    enableImages: true,
                    enableUserData: true
                )
            )
        ).value.items) ?? []
        episodes = result
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
                return resumeEp
            }
            if !fromBeginning, let unplayed = episodes.first(where: { ($0.userData?.isPlayed ?? false) == false }) {
                return unplayed
            }
            return episodes.first
        }
        if displayItem?.type == .boxSet {
            guard let firstItem = collectionItems.first(where: { $0.type == .movie || $0.type == .series }) ?? collectionItems.first else {
                return nil
            }
            if firstItem.type == .series {
                if !fromBeginning, let resumeEp = libraryViewModel?.resumeShows.first(where: { $0.seriesID == firstItem.id }) {
                    return resumeEp
                }
                let matching = (libraryViewModel?.episodes ?? [])
                    .filter { $0.seriesID == firstItem.id }
                    .sorted { a, b in
                        let sA = a.parentIndexNumber ?? 1
                        let sB = b.parentIndexNumber ?? 1
                        if sA != sB { return sA < sB }
                        return (a.indexNumber ?? 1) < (b.indexNumber ?? 1)
                    }
                if !fromBeginning, let unplayed = matching.first(where: { ($0.userData?.isPlayed ?? false) == false }) {
                    return unplayed
                }
                if let firstEp = matching.first {
                    return firstEp
                }
            }
            return firstItem
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

    func setFavorite(_ isFavorite: Bool, serverViewModel: ServerViewModel?) {
        guard let serverViewModel, let itemID = displayItem?.id else { return }
        let current = self.isFavorite
        detailedItem?.setFavorite(isFavorite)
        sourceItem?.setFavorite(isFavorite)
        Task {
            let result = await serverViewModel.setFavorite(isFavorite, forItemID: itemID)
            if result == nil {
                detailedItem?.setFavorite(current)
                sourceItem?.setFavorite(current)
            }
        }
    }

    func handleFavoriteNotification(itemID: String, isFavorite: Bool) {
        if displayItem?.id == itemID {
            detailedItem?.setFavorite(isFavorite)
            sourceItem?.setFavorite(isFavorite)
        }
    }

    func loadCollectionItems(client: JellyfinClient, userID: String?) async {
        guard let collectionID = sourceItem?.id ?? detailedItem?.id else { return }
        isLoadingCollectionItems = true
        defer { isLoadingCollectionItems = false }

        var params = Paths.GetItemsParameters()
        params.userID = userID
        params.parentID = collectionID
        params.isRecursive = true
        params.isCollapseBoxSetItems = false
        params.fields = [.primaryImageAspectRatio, .genres, .tags, .overview]
        params.enableUserData = userID != nil
        params.enableImages = true

        let items = (try? await client.send(Paths.getItems(parameters: params)).value.items) ?? []

        collectionItems = items.sorted { a, b in
            let dateA = a.premiereDate ?? (a.productionYear.flatMap { Calendar.current.date(from: DateComponents(year: $0)) } ?? .distantPast)
            let dateB = b.premiereDate ?? (b.productionYear.flatMap { Calendar.current.date(from: DateComponents(year: $0)) } ?? .distantPast)
            if dateA != dateB {
                return dateA < dateB
            }
            return (a.sortName ?? a.name ?? "") < (b.sortName ?? b.name ?? "")
        }
    }

}
