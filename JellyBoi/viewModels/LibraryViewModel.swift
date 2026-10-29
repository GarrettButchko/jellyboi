//
//  LibraryViewModel.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 8/28/26.
//

import Foundation
import SwiftUI
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

    // MARK: - Normalized store

    private var itemsByID: [String: BaseItemDto] = [:]

    // MARK: - Ordered ID lists

    private(set) var movieIDs: [String] = []
    private(set) var tvShowIDs: [String] = []
    private(set) var episodeIDs: [String] = []
    private(set) var collectionIDs: [String] = []
    private(set) var recommendedIDs: [String] = []
    private(set) var recentlyAddedMovieIDs: [String] = []
    private(set) var recentlyAddedShowIDs: [String] = []
    private(set) var recentlyAddedIDs: [String] = []
    private(set) var resumeShowIDs: [String] = []

    // MARK: - Derived library data

    var movies: [BaseItemDto] { movieIDs.compactMap { itemsByID[$0] } }
    var tvShows: [BaseItemDto] { tvShowIDs.compactMap { itemsByID[$0] } }
    var episodes: [BaseItemDto] { episodeIDs.compactMap { itemsByID[$0] } }
    var collections: [BaseItemDto] { collectionIDs.compactMap { itemsByID[$0] } }
    var recommended: [BaseItemDto] { recommendedIDs.compactMap { itemsByID[$0] } }
    var recentlyAddedMovies: [BaseItemDto] { recentlyAddedMovieIDs.compactMap { itemsByID[$0] } }
    var recentlyAddedShows: [BaseItemDto] { recentlyAddedShowIDs.compactMap { itemsByID[$0] } }
    var recentlyAdded: [BaseItemDto] { recentlyAddedIDs.compactMap { itemsByID[$0] } }
    var resumeShows: [BaseItemDto] { resumeShowIDs.compactMap { itemsByID[$0] } }

    // MARK: - Lookup & Store Helpers

    func item(for itemID: String) -> BaseItemDto? {
        itemsByID[itemID]
    }

    func updateItem(_ item: BaseItemDto) {
        guard let id = item.id else { return }
        itemsByID[id] = item
    }

    // MARK: - Home aggregates

    private(set) var inProgressMovies: [BaseItemDto] = []
    private(set) var topWatchedMovies: [BaseItemDto] = []
    private(set) var tvSeriesCount: Int = 0
    private(set) var episodeCount: Int = 0
    private(set) var favoritesCount: Int = 0
    private(set) var completedCount: Int = 0
    private(set) var watchedHours: Int = 0

    // MARK: - Similar items cache

    private var similarItemsCache: [String: [BaseItemDto]] = [:]

    func cachedSimilarItems(for itemID: String) -> [BaseItemDto]? {
        similarItemsCache[itemID]
    }

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

    // MARK: - Special features cache

    private var specialFeaturesCache: [String: [BaseItemDto]] = [:]

    func cachedSpecialFeatures(for itemID: String) -> [BaseItemDto]? {
        specialFeaturesCache[itemID]
    }

    func specialFeatures(for itemID: String, client: JellyfinClient, userID: String?) async -> [BaseItemDto] {
        if let cached = specialFeaturesCache[itemID] { return cached }
        let result = (try? await client.send(
            Paths.getSpecialFeatures(itemID: itemID, userID: userID)
        ).value) ?? []
        specialFeaturesCache[itemID] = result
        return result
    }

    // MARK: - Lifecycle

    @ObservationIgnored
    private var progressResetTask: Task<Void, Never>?
    @ObservationIgnored
    private var progressUpdateTask: Task<Void, Never>?
    @ObservationIgnored
    private var favoriteToggleTask: Task<Void, Never>?
    @ObservationIgnored
    private var isFetching = false
    @ObservationIgnored
    private var currentUserID: String?

    init() {
        progressResetTask = Task { @MainActor [weak self] in
            for await notification in NotificationCenter.default.notifications(named: .mediaProgressReset) {
                guard let self else { break }
                if let itemID = notification.object as? String {
                    withAnimation(.smooth(duration: 0.35)) {
                        self.clearProgress(for: itemID)
                    }
                }
            }
        }
        progressUpdateTask = Task { @MainActor [weak self] in
            for await notification in NotificationCenter.default.notifications(named: .mediaProgressUpdated) {
                guard let self else { break }
                if let itemID = notification.object as? String,
                   let positionTicks = notification.userInfo?["positionTicks"] as? Int {
                    let totalTicks = notification.userInfo?["durationTicks"] as? Int
                    withAnimation(.smooth(duration: 0.35)) {
                        self.updateProgress(for: itemID, positionTicks: positionTicks, totalTicks: totalTicks)
                    }
                }
            }
        }
        favoriteToggleTask = Task { @MainActor [weak self] in
            for await notification in NotificationCenter.default.notifications(named: .mediaFavoriteToggled) {
                guard let self else { break }
                if let itemID = notification.object as? String,
                   let isFavorite = notification.userInfo?["isFavorite"] as? Bool {
                    let userData = notification.userInfo?["userData"] as? UserItemDataDto
                    withAnimation(.smooth(duration: 0.35)) {
                        self.updateFavorite(for: itemID, isFavorite: isFavorite, userData: userData)
                    }
                }
            }
        }
    }

    deinit {
        progressResetTask?.cancel()
        progressUpdateTask?.cancel()
        favoriteToggleTask?.cancel()
    }

    // MARK: - State

    var isLoading = true
    var errorMessage: String?

    /// True when no media of any kind has been fetched yet (brand-new or fully empty library).
    var isLibraryEmpty: Bool { movieIDs.isEmpty && tvShowIDs.isEmpty && episodeIDs.isEmpty }

    func load(using client: JellyfinClient, userID: String? = nil) async {
        guard movieIDs.isEmpty && tvShowIDs.isEmpty && episodeIDs.isEmpty else { return }
        guard !isFetching else { return }
        await refresh(using: client, userID: userID)
    }

    func refresh(using client: JellyfinClient, userID: String? = nil) async {
        guard !isFetching else { return }
        isFetching = true
        defer { isFetching = false }

        if let userID {
            self.currentUserID = userID
        }
        let effectiveUserID = userID ?? currentUserID

        let isInitialLoad = movieIDs.isEmpty && tvShowIDs.isEmpty && episodeIDs.isEmpty
        if isInitialLoad {
            isLoading = true
        }
        defer { isLoading = false }

        do {
            let moviesParams = Paths.GetItemsParameters(
                userID: effectiveUserID,
                isRecursive: true, sortOrder: [.ascending],
                fields: [.genres, .tags, .overview, .primaryImageAspectRatio],
                includeItemTypes: [.movie], sortBy: [.sortName],
                enableUserData: true
            )

            let showsParams = Paths.GetItemsParameters(
                userID: effectiveUserID,
                isRecursive: true, sortOrder: [.ascending],
                fields: [.genres, .tags, .overview, .childCount, .recursiveItemCount, .primaryImageAspectRatio],
                includeItemTypes: [.series], sortBy: [.sortName],
                enableUserData: true
            )

            let episodesParams = Paths.GetItemsParameters(
                userID: effectiveUserID,
                isRecursive: true, sortOrder: [.ascending],
                fields: [.genres, .tags, .overview, .primaryImageAspectRatio],
                includeItemTypes: [.episode], sortBy: [.seriesSortName, .sortName],
                enableUserData: true
            )

            let episodesCountParams = Paths.GetItemsParameters(
                userID: effectiveUserID,
                limit: 0,
                isRecursive: true,
                includeItemTypes: [.episode]
            )

            let collectionsParams = Paths.GetItemsParameters(
                userID: effectiveUserID,
                isRecursive: true,
                sortOrder: [.ascending],
                fields: [.genres, .tags, .overview, .primaryImageAspectRatio],
                includeItemTypes: [.boxSet],
                sortBy: [.sortName],
                enableUserData: true
            )

            let recommendedParams = Paths.GetItemsParameters(
                userID: effectiveUserID,
                limit: 20, isRecursive: true,
                sortOrder: [.descending],
                includeItemTypes: [.movie, .series],
                sortBy: [.communityRating]
            )

            let recentMoviesParams = Paths.GetItemsParameters(
                userID: effectiveUserID,
                limit: 20, isRecursive: true,
                sortOrder: [.descending],
                includeItemTypes: [.movie],
                sortBy: [.dateCreated],
                enableUserData: true
            )

            let recentShowsParams = Paths.GetItemsParameters(
                userID: effectiveUserID,
                limit: 20, isRecursive: true,
                sortOrder: [.descending],
                includeItemTypes: [.series],
                sortBy: [.dateCreated],
                enableUserData: true
            )

            let nextUpParams = Paths.GetNextUpParameters(limit: 20, enableResumable: true)
            let favoritesCountParams = Paths.GetItemsParameters(
                userID: effectiveUserID,
                limit: 0, isRecursive: true, filters: [.isFavorite]
            )

            async let moviesResponse       = client.send(Paths.getItems(parameters: moviesParams))
            async let showsResponse        = client.send(Paths.getItems(parameters: showsParams))
            async let episodesResponse     = try? client.send(Paths.getItems(parameters: episodesParams))
            async let episodeCountResponse = try? client.send(Paths.getItems(parameters: episodesCountParams))
            async let collectionsResponse  = try? client.send(Paths.getItems(parameters: collectionsParams))
            async let recommendedResponse  = try? client.send(Paths.getItems(parameters: recommendedParams))
            async let recentMoviesResponse = try? client.send(Paths.getItems(parameters: recentMoviesParams))
            async let recentShowsResponse  = try? client.send(Paths.getItems(parameters: recentShowsParams))
            async let nextUpResponse       = try? client.send(Paths.getNextUp(parameters: nextUpParams))
            async let favoritesResponse    = try? client.send(Paths.getItems(parameters: favoritesCountParams))

            let fetchedMovies        = (try await moviesResponse).value.items ?? []
            let fetchedShows         = (try await showsResponse).value.items ?? []
            let fetchedEpisodes      = (await episodesResponse)?.value.items ?? []
            let fetchedEpisodeCount  = (await episodeCountResponse)?.value.totalRecordCount ?? 0
            let fetchedCollections   = (await collectionsResponse)?.value.items ?? []
            let fetchedRecommended   = (await recommendedResponse)?.value.items ?? []
            let fetchedRecentMovies  = (await recentMoviesResponse)?.value.items ?? []
            let fetchedRecentShows   = (await recentShowsResponse)?.value.items ?? []
            let fetchedRecent        = (fetchedRecentMovies + fetchedRecentShows).sorted {
                ($0.dateCreated ?? .distantPast) > ($1.dateCreated ?? .distantPast)
            }
            let fetchedNextUp        = (await nextUpResponse)?.value.items ?? []
            let fetchedFavorites     = (await favoritesResponse)?.value.totalRecordCount ?? 0

            var newItemsByID: [String: BaseItemDto] = [:]

            func record(_ items: [BaseItemDto]) -> [String] {
                var ids: [String] = []
                ids.reserveCapacity(items.count)
                for item in items {
                    guard let id = item.id else { continue }
                    if newItemsByID[id] == nil {
                        newItemsByID[id] = item
                    }
                    ids.append(id)
                }
                return ids
            }

            let recordedMovieIDs         = record(fetchedMovies)
            let recordedShowIDs          = record(fetchedShows)
            let recordedEpisodeIDs       = record(fetchedEpisodes)
            let recordedCollectionIDs    = record(fetchedCollections)
            let recordedRecommendedIDs   = record(fetchedRecommended)
            let recordedRecentMovieIDs   = record(fetchedRecentMovies)
            let recordedRecentShowIDs    = record(fetchedRecentShows)
            let recordedRecentIDs        = record(fetchedRecent)
            let recordedNextUpIDs        = record(fetchedNextUp)

            withAnimation(.smooth(duration: 0.45)) {
                itemsByID             = newItemsByID
                movieIDs              = recordedMovieIDs
                tvShowIDs             = recordedShowIDs
                episodeIDs            = recordedEpisodeIDs
                collectionIDs         = recordedCollectionIDs
                recommendedIDs        = recordedRecommendedIDs
                recentlyAddedMovieIDs = recordedRecentMovieIDs
                recentlyAddedShowIDs  = recordedRecentShowIDs
                recentlyAddedIDs      = recordedRecentIDs
                resumeShowIDs         = recordedNextUpIDs
                favoritesCount        = fetchedFavorites
                tvSeriesCount         = fetchedShows.count
                episodeCount          = fetchedEpisodes.count > 0 ? fetchedEpisodes.count : fetchedEpisodeCount

                updateAggregates()
            }

            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Progress Management

    func clearProgress(for itemID: String) {
        if var item = itemsByID[itemID] {
            item.clearProgress()
            itemsByID[itemID] = item
        }
        for (id, var item) in itemsByID where item.seriesID == itemID {
            item.clearProgress()
            itemsByID[id] = item
        }
        resumeShowIDs.removeAll { id in
            guard let item = itemsByID[id] else { return true }
            return item.id == itemID || item.seriesID == itemID
        }

        updateAggregates()
    }

    func updateProgress(for itemID: String, positionTicks: Int, totalTicks: Int?) {
        if var item = itemsByID[itemID] {
            item.updateProgress(positionTicks: positionTicks, totalTicks: totalTicks)
            itemsByID[itemID] = item
        }

        updateAggregates()
    }

    // MARK: - Favorite Management

    func updateFavorite(for itemID: String, isFavorite: Bool, userData: UserItemDataDto? = nil) {
        guard var item = itemsByID[itemID] else { return }
        let wasFavorite = item.userData?.isFavorite ?? false

        if let userData {
            item.userData = userData
        } else {
            item.setFavorite(isFavorite)
        }
        itemsByID[itemID] = item

        if wasFavorite != isFavorite {
            favoritesCount = max(0, favoritesCount + (isFavorite ? 1 : -1))
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
        if item.type == .episode && (item.imageTags?.keys.contains("Primary") != true) {
            return seriesPosterURL(for: item, client: client)
        }
        return client.url(with: Paths.getItemImage(
            itemID: id,
            imageType: "Primary",
            parameters: .init(maxWidth: 400, quality: 80)
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
        let hasThumb = item.imageTags?.keys.contains("Thumb") == true
        let hasBackdrop = !(item.backdropImageTags ?? []).isEmpty || item.imageTags?.keys.contains("Backdrop") == true
        let imageType: String
        let targetID: String

        if hasThumb {
            imageType = "Thumb"
            targetID = id
        } else if hasBackdrop {
            imageType = "Backdrop"
            targetID = id
        } else if item.type == .episode, item.imageTags?.keys.contains("Primary") == true {
            imageType = "Primary"
            targetID = id
        } else if let seriesID = item.seriesID {
            imageType = "Thumb"
            targetID = seriesID
        } else {
            imageType = "Backdrop"
            targetID = id
        }

        return client.url(with: Paths.getItemImage(
            itemID: targetID,
            imageType: imageType,
            parameters: .init(maxWidth: 1920, quality: 96)
        ))
    }

    // MARK: - Prefetching

    func prefetchBackdrops(around index: Int, items: [BaseItemDto]? = nil, client: JellyfinClient) {
        let targetItems = items ?? movies
        let neighbors = [index - 1, index, index + 1]
            .filter { $0 >= 0 && $0 < targetItems.count }
        let urls = neighbors.compactMap { backdropURL(for: targetItems[$0], client: client) }
        SDWebImagePrefetcher.shared.prefetchURLs(urls)
    }

    func prefetchPosters(around index: Int, client: JellyfinClient) {
        let neighbors = [index - 1, index, index + 1]
            .filter { $0 >= 0 && $0 < movies.count }
        let urls = neighbors.compactMap { posterURL(for: movies[$0], client: client) }
        SDWebImagePrefetcher.shared.prefetchURLs(urls)
    }
}
