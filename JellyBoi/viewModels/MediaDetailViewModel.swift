//
//  MediaDetailViewModel.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 8/31/26.
//

import Foundation
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

    var selectedSeason: BaseItemDto? {
        guard seasons.indices.contains(selectedSeasonIndex) else { return nil }
        return seasons[selectedSeasonIndex]
    }

    private var client: JellyfinClient?
    private var sourceItem: BaseItemDto?

    private var displayItem: BaseItemDto? { detailedItem ?? sourceItem }

    var backdropURL: URL? {
        guard let client, let id = displayItem?.id else { return nil }
        let hasBackdrop = !(displayItem?.backdropImageTags ?? []).isEmpty
        if hasBackdrop {
            return client.url(with: Paths.getItemImageByIndex(
                itemID: id,
                imageType: "Backdrop",
                imageIndex: 0,
                parameters: .init(maxWidth: 800, quality: 90)
            ))
        }
        return client.url(with: Paths.getItemImage(
            itemID: id,
            imageType: "Primary",
            parameters: .init(maxWidth: 800, quality: 90)
        ))
    }

    var posterURL: URL? {
        guard let client, let id = displayItem?.id else { return nil }
        return client.url(with: Paths.getItemImage(
            itemID: id,
            imageType: "Primary",
            parameters: .init(maxWidth: 600, quality: 90)
        ))
    }

    func markHeroReady() {
        heroReady = true
    }

    var logoURL: URL? {
        guard let client,
              let item = displayItem,
              let id = item.id,
              item.imageTags?["Logo"] != nil else { return nil }
        return client.url(with: Paths.getItemImage(
            itemID: id,
            imageType: "Logo",
            parameters: .init(maxWidth: 400, quality: 90)
        ))
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

        if item.type == .series {
            await loadSeasonsAndEpisodes(client: client, userID: userID)
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

}
