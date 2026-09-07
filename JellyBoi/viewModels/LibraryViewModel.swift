//
//  LibraryViewModel.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 8/28/26.
//

import Foundation
import Observation
import Get
import JellyfinAPI
import SDWebImage

/// Owns all of the media fetched from the server. This is fetched **once** when a
/// client becomes available and is shared across every tab. Individual tab view
/// models read from this shared source and filter/derive what they need locally.
@Observable
@MainActor
class LibraryViewModel {

    // MARK: - Raw library data

    private(set) var movies: [BaseItemDto] = []
    private(set) var tvShows: [BaseItemDto] = []
    private(set) var episodes: [BaseItemDto] = []

    // MARK: - Home aggregates

    private(set) var collections: [BaseItemDto] = []
    private(set) var recommended: [BaseItemDto] = []
    private(set) var recentlyAdded: [BaseItemDto] = []
    private(set) var resumeShows: [BaseItemDto] = []
    private(set) var inProgressMovies: [BaseItemDto] = []
    private(set) var topWatchedMovies: [BaseItemDto] = []
    private(set) var tvSeriesCount: Int = 0
    private(set) var episodeCount: Int = 0
    private(set) var favoritesCount: Int = 0
    private(set) var completedCount: Int = 0
    private(set) var watchedHours: Int = 0

    // MARK: - Similar items cache

    private var similarItemsCache: [String: [BaseItemDto]] = [:]

    func similarItems(for itemID: String, client: JellyfinClient, userID: String?) async -> [BaseItemDto] {
        if let cached = similarItemsCache[itemID] { return cached }
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
        similarItemsCache[itemID] = result
        return result
    }

    // MARK: - State

    var isLoading = true
    var errorMessage: String?

    /// True when no media of any kind has been fetched yet (brand-new or fully empty library).
    var isLibraryEmpty: Bool { movies.isEmpty && tvShows.isEmpty && episodes.isEmpty }

    func load(using client: JellyfinClient) async {
        guard movies.isEmpty && tvShows.isEmpty else { return }
        await refresh(using: client)
    }

    func refresh(using client: JellyfinClient) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let moviesParams = Paths.GetItemsParameters(
                isRecursive: true, sortOrder: [.ascending],
                fields: [.genres, .tags],
                includeItemTypes: [.movie], sortBy: [.sortName]
            )
            let showsParams = Paths.GetItemsParameters(
                isRecursive: true, sortOrder: [.ascending],
                fields: [.genres, .tags],
                includeItemTypes: [.series], sortBy: [.sortName]
            )
            let episodesParams = Paths.GetItemsParameters(
                isRecursive: true, sortOrder: [.ascending],
                includeItemTypes: [.episode], sortBy: [.sortName]
            )
            let collectionsParams = Paths.GetItemsParameters(
                isRecursive: true,
                sortOrder: [.ascending],
                includeItemTypes: [.boxSet],
                sortBy: [.sortName]
            )
            let recommendedParams = Paths.GetItemsParameters(
                limit: 20, isRecursive: true,
                sortOrder: [.descending],
                includeItemTypes: [.movie, .series],
                sortBy: [.communityRating]
            )
            let recentParams = Paths.GetItemsParameters(
                limit: 20, isRecursive: true,
                sortOrder: [.descending],
                includeItemTypes: [.movie, .series],
                sortBy: [.dateCreated]
            )
            let nextUpParams = Paths.GetNextUpParameters(limit: 20, enableResumable: true)
            let favoritesCountParams = Paths.GetItemsParameters(
                limit: 0, isRecursive: true, filters: [.isFavorite]
            )

            async let moviesResult      = client.send(Paths.getItems(parameters: moviesParams)).value.items
            async let showsResult       = client.send(Paths.getItems(parameters: showsParams)).value.items
            async let episodesResult    = client.send(Paths.getItems(parameters: episodesParams)).value.items
            async let collectionsResult = client.send(Paths.getItems(parameters: collectionsParams)).value.items
            async let recommendedResult = client.send(Paths.getItems(parameters: recommendedParams)).value.items
            async let recentResult      = client.send(Paths.getItems(parameters: recentParams)).value.items
            async let nextUpResult      = client.send(Paths.getNextUp(parameters: nextUpParams)).value.items
            async let favoritesResult   = client.send(Paths.getItems(parameters: favoritesCountParams)).value.totalRecordCount

            movies        = try await moviesResult ?? []
            tvShows       = try await showsResult ?? []
            episodes      = try await episodesResult ?? []
            collections   = try await collectionsResult ?? []
            recommended   = try await recommendedResult ?? []
            recentlyAdded = try await recentResult ?? []
            resumeShows   = try await nextUpResult ?? []
            favoritesCount = try await favoritesResult ?? 0
            tvSeriesCount  = tvShows.count
            episodeCount   = episodes.count

            updateAggregates()

            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Aggregates

    private func updateAggregates() {
        inProgressMovies = movies
            .filter {
                guard let percent = $0.userData?.playedPercentage else { return false }
                return percent > 0 && percent < 85
            }
            .sorted {
                ($0.userData?.lastPlayedDate ?? .distantPast) > ($1.userData?.lastPlayedDate ?? .distantPast)
            }
        topWatchedMovies = Array(
            inProgressMovies.sorted {
                let a = (($0.userData?.playedPercentage ?? 0) / 100.0) * Double($0.runTimeTicks ?? 0)
                let b = (($1.userData?.playedPercentage ?? 0) / 100.0) * Double($1.runTimeTicks ?? 0)
                return a > b
            }.prefix(6)
        )
        completedCount = movies.filter { $0.userData?.isPlayed == true }.count
        watchedHours = Int(
            movies.reduce(0.0) { acc, item in
                guard let ticks = item.runTimeTicks,
                      let percent = item.userData?.playedPercentage, percent > 0 else { return acc }
                return acc + (percent / 100.0) * Double(ticks) / 10_000_000
            } / 3_600
        )
    }

    // MARK: - Image URLs

    func posterURL(for item: BaseItemDto, client: JellyfinClient) -> URL? {
        guard let id = item.id else { return nil }
        return client.url(with: Paths.getItemImage(
            itemID: id,
            imageType: "Primary",
            parameters: .init(maxWidth: 400, quality: 80)
        ))
    }

    func backgroundURL(for item: BaseItemDto, client: JellyfinClient) -> URL? {
        guard let id = item.id else { return nil }
        return client.url(with: Paths.getItemImage(
            itemID: id,
            imageType: "Backdrop",
            parameters: .init(maxWidth: 800, quality: 80)
        ))
    }

    func seriesPosterURL(for episode: BaseItemDto, client: JellyfinClient) -> URL? {
        let itemID = episode.seriesID ?? episode.id
        guard let itemID else { return nil }
        return client.url(with: Paths.getItemImage(
            itemID: itemID,
            imageType: "Primary",
            parameters: .init(maxWidth: 400, quality: 80)
        ))
    }

    func backdropURL(for item: BaseItemDto, client: JellyfinClient) -> URL? {
        guard let id = item.id else { return nil }
        let imageType = item.imageTags?.keys.contains("Thumb") == true ? "Thumb" : "Backdrop"
        return client.url(with: Paths.getItemImage(
            itemID: id,
            imageType: imageType,
            parameters: .init(maxWidth: 600, quality: 85)
        ))
    }

    // MARK: - Prefetching

    func prefetchBackdrops(around index: Int, client: JellyfinClient) {
        let neighbors = [index - 1, index, index + 1]
            .filter { $0 >= 0 && $0 < movies.count }
        let urls = neighbors.compactMap { backgroundURL(for: movies[$0], client: client) }
        SDWebImagePrefetcher.shared.prefetchURLs(urls)
    }

    func prefetchPosters(around index: Int, client: JellyfinClient) {
        let neighbors = [index - 1, index, index + 1]
            .filter { $0 >= 0 && $0 < movies.count }
        let urls = neighbors.compactMap { posterURL(for: movies[$0], client: client) }
        SDWebImagePrefetcher.shared.prefetchURLs(urls)
    }
}
