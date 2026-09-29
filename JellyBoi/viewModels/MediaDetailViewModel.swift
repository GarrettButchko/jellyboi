//
//  MediaDetailViewModel.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 8/31/26.
//

import Foundation
import SwiftUI
import Observation
import Get
import JellyfinAPI

/// Loads the full `BaseItemDto` (with people, studios, ratings, tags) and
/// similar items for the given media item on appear. `MediaDetailView` renders
/// immediately from the data-poor library item and upgrades when this finishes.
@Observable
@MainActor
class MediaDetailViewModel {

    private(set) var detailedItem: BaseItemDto?
    private(set) var similarItems: [BaseItemDto] = []
    private(set) var heroReady: Bool = false
    var isLoading = false

    private(set) var seasons: [BaseItemDto] = []
    private(set) var episodes: [BaseItemDto] = []
    var selectedSeasonIndex: Int = 0

    private(set) var collectionItems: [BaseItemDto] = []
    private(set) var isLoadingCollectionItems: Bool = false

    var selectedSeason: BaseItemDto? {
        guard seasons.indices.contains(selectedSeasonIndex) else { return nil }
        return seasons[selectedSeasonIndex]
    }

    private var client: JellyfinClient?
    private(set) var sourceItem: BaseItemDto?

    private var displayItem: BaseItemDto? { detailedItem ?? sourceItem }

    var heroAspectRatio: CGFloat
    private(set) var hasDetectedBitmapRatio = false

    init(item: BaseItemDto? = nil, client: JellyfinClient? = nil) {
        self.sourceItem = item
        self.client = client
        self.heroAspectRatio = item?.imageAspectRatio ?? (2.0 / 3.0)
    }

    func prepare(item: BaseItemDto, client: JellyfinClient?) {
        if self.sourceItem == nil { self.sourceItem = item }
        if self.client == nil { self.client = client }
        if !hasDetectedBitmapRatio && abs(heroAspectRatio - item.imageAspectRatio) > 0.005 {
            self.heroAspectRatio = item.imageAspectRatio
        }
    }

    func updateHeroAspectRatio(from size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        hasDetectedBitmapRatio = true
        let actualRatio = size.width / size.height
        if abs(heroAspectRatio - actualRatio) > 0.005 {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                heroAspectRatio = actualRatio
            }
        }
    }

    var backdropURL: URL? {
        backdropURL(client: nil)
    }

    func backdropURL(client fallbackClient: JellyfinClient? = nil) -> URL? {
        let activeClient = client ?? fallbackClient
        guard let activeClient, let id = displayItem?.id else { return nil }
        let hasBackdrop = !(displayItem?.backdropImageTags ?? []).isEmpty
        if hasBackdrop {
            return activeClient.url(with: Paths.getItemImageByIndex(
                itemID: id,
                imageType: "Backdrop",
                imageIndex: 0,
                parameters: .init(maxWidth: 800, quality: 90)
            ))
        }
        return activeClient.url(with: Paths.getItemImage(
            itemID: id,
            imageType: "Primary",
            parameters: .init(maxWidth: 800, quality: 90)
        ))
    }

    var posterURL: URL? {
        posterURL(client: nil)
    }

    func posterURL(client fallbackClient: JellyfinClient? = nil) -> URL? {
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

    func episodeThumbnailURL(for episode: BaseItemDto) -> URL? {
        guard let client, let id = episode.id else { return nil }
        let imageType = episode.imageTags?.keys.contains("Thumb") == true ? "Thumb" : "Primary"
        return client.url(with: Paths.getItemImage(
            itemID: id,
            imageType: imageType,
            parameters: .init(maxWidth: 600, quality: 90)
        ))
    }

    // MARK: - Progress Management

    func clearProgress(for itemID: String) {
        if detailedItem?.id == itemID {
            detailedItem?.clearProgress()
        }
        episodes.clearProgress(for: itemID, matchingSeries: true)
        collectionItems.clearProgress(for: itemID)
    }

    // MARK: - Favorite Management

    var isFavorite: Bool {
        isFavorite()
    }

    func isFavorite(fallback: BaseItemDto? = nil) -> Bool {
        detailedItem?.isFavorite ?? sourceItem?.isFavorite ?? fallback?.isFavorite ?? false
    }

    func setFavoriteLocally(_ isFavorite: Bool) {
        detailedItem?.setFavorite(isFavorite)
        sourceItem?.setFavorite(isFavorite)
    }

    func toggleFavorite(serverViewModel: ServerViewModel?, fallbackItem: BaseItemDto? = nil) async {
        if sourceItem == nil, let fallbackItem {
            sourceItem = fallbackItem
        }
        guard let itemID = displayItem?.id ?? fallbackItem?.id, let serverViewModel else { return }
        let currentFavorite = isFavorite(fallback: fallbackItem)
        let newFavorite = !currentFavorite

        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            setFavoriteLocally(newFavorite)
        }

        let result = await serverViewModel.setFavorite(newFavorite, forItemID: itemID)
        if result == nil {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                setFavoriteLocally(currentFavorite)
            }
        }
    }

    func handleFavoriteToggled(itemID: String, isFavorite: Bool) {
        if displayItem?.id == itemID || sourceItem?.id == itemID {
            setFavoriteLocally(isFavorite)
        }
    }

    // MARK: - Collection Items

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
