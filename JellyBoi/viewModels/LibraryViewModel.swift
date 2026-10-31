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

/// Immutable snapshot containing processed library data and computed aggregates, safe for transfer across actors.
struct LibraryDataSnapshot: Sendable {
    let itemsByID: [String: BaseItemDto]
    let movieIDs: [String]
    let tvShowIDs: [String]
    let episodeIDs: [String]
    let collectionIDs: [String]
    let recommendedIDs: [String]
    let recentlyAddedMovieIDs: [String]
    let recentlyAddedShowIDs: [String]
    let recentlyAddedIDs: [String]
    let resumeShowIDs: [String]
    let favoritesCount: Int
    let tvSeriesCount: Int
    let episodeCount: Int

    let movies: [BaseItemDto]
    let tvShows: [BaseItemDto]
    let episodes: [BaseItemDto]
    let collections: [BaseItemDto]
    let recommended: [BaseItemDto]
    let recentlyAddedMovies: [BaseItemDto]
    let recentlyAddedShows: [BaseItemDto]
    let recentlyAdded: [BaseItemDto]
    let resumeShows: [BaseItemDto]
    let episodesBySeriesID: [String: [BaseItemDto]]
    let inProgressMovies: [BaseItemDto]
    let topWatchedMovies: [BaseItemDto]
    let carouselItems: [BaseItemDto]
    let genres: [GenreCount]
    let completedCount: Int
    let watchedHours: Int
}

/// Owns all of the media fetched from the server. This is fetched **once** when a
/// client becomes available and is shared across every tab. Individual tab view
/// models read from this shared source and filter/derive what they need locally.
@Observable
@MainActor
class LibraryViewModel {

    // MARK: - Normalized store

    @ObservationIgnored
    private var itemsByID: [String: BaseItemDto] = [:]

    // MARK: - Ordered ID lists

    @ObservationIgnored
    private(set) var movieIDs: [String] = []
    @ObservationIgnored
    private(set) var tvShowIDs: [String] = []
    @ObservationIgnored
    private(set) var episodeIDs: [String] = []
    @ObservationIgnored
    private(set) var collectionIDs: [String] = []
    @ObservationIgnored
    private(set) var recommendedIDs: [String] = []
    @ObservationIgnored
    private(set) var recentlyAddedMovieIDs: [String] = []
    @ObservationIgnored
    private(set) var recentlyAddedShowIDs: [String] = []
    @ObservationIgnored
    private(set) var recentlyAddedIDs: [String] = []
    @ObservationIgnored
    private(set) var resumeShowIDs: [String] = []

    // MARK: - Derived library data (Cached for instant O(1) access during scrolling)

    private(set) var movies: [BaseItemDto] = []
    private(set) var tvShows: [BaseItemDto] = []
    private(set) var episodes: [BaseItemDto] = []
    private(set) var collections: [BaseItemDto] = []
    private(set) var recommended: [BaseItemDto] = []
    private(set) var recentlyAddedMovies: [BaseItemDto] = []
    private(set) var recentlyAddedShows: [BaseItemDto] = []
    private(set) var recentlyAdded: [BaseItemDto] = []
    private(set) var resumeShows: [BaseItemDto] = []
    private(set) var carouselItems: [BaseItemDto] = []
    private(set) var genres: [GenreCount] = []
    @ObservationIgnored
    private(set) var episodesBySeriesID: [String: [BaseItemDto]] = [:]

    func episodes(forSeriesID seriesID: String) -> [BaseItemDto] {
        episodesBySeriesID[seriesID] ?? []
    }

    // MARK: - Lookup & Store Helpers

    func item(for itemID: String) -> BaseItemDto? {
        itemsByID[itemID]
    }

    func updateItem(_ item: BaseItemDto) {
        guard let id = item.id else { return }
        itemsByID[id] = item
        updateAggregates()
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
        let result = await client.fetchSimilarItems(itemID: itemID, userID: userID, limit: 12)
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
        let result = await client.fetchSpecialFeatures(itemID: itemID, userID: userID)
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
        if let userID {
            self.currentUserID = userID
        }
        guard movieIDs.isEmpty && tvShowIDs.isEmpty && episodeIDs.isEmpty else { return }
        guard !isFetching else { return }
        await refresh(using: client, userID: userID ?? currentUserID)
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
            let snapshot = try await Task.detached(priority: .userInitiated) {
                try await Self.fetchAndProcessData(using: client, userID: effectiveUserID)
            }.value

            apply(snapshot)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private nonisolated static func fetchAndProcessData(
        using client: JellyfinClient,
        userID: String?
    ) async throws -> LibraryDataSnapshot {
        let moviesParams = Paths.GetItemsParameters.movies(userID: userID)
        let showsParams = Paths.GetItemsParameters.tvShows(userID: userID)
        let episodesParams = Paths.GetItemsParameters.episodes(userID: userID)
        let episodesCountParams = Paths.GetItemsParameters.countOnly(userID: userID, types: [.episode])
        let collectionsParams = Paths.GetItemsParameters.collections(userID: userID)
        let recommendedParams = Paths.GetItemsParameters.recommended(userID: userID)
        let recentMoviesParams = Paths.GetItemsParameters.recentMovies(userID: userID)
        let recentShowsParams = Paths.GetItemsParameters.recentShows(userID: userID)
        let nextUpParams = Paths.GetNextUpParameters.standard(userID: userID, limit: 20)
        let favoritesCountParams = Paths.GetItemsParameters.countOnly(userID: userID, filters: [.isFavorite])

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

        let movies = recordedMovieIDs.compactMap { newItemsByID[$0] }
        let tvShows = recordedShowIDs.compactMap { newItemsByID[$0] }
        let episodes = recordedEpisodeIDs.compactMap { newItemsByID[$0] }
        let collections = recordedCollectionIDs.compactMap { newItemsByID[$0] }
        let recommended = recordedRecommendedIDs.compactMap { newItemsByID[$0] }
        let recentlyAddedMovies = recordedRecentMovieIDs.compactMap { newItemsByID[$0] }
        let recentlyAddedShows = recordedRecentShowIDs.compactMap { newItemsByID[$0] }
        let recentlyAdded = recordedRecentIDs.compactMap { newItemsByID[$0] }
        let resumeShows = recordedNextUpIDs
            .compactMap { newItemsByID[$0] }
            .filter { !$0.isUnplayedFirstEpisode }

        var grouped: [String: [BaseItemDto]] = [:]
        for ep in episodes {
            if let seriesID = ep.seriesID {
                grouped[seriesID, default: []].append(ep)
            }
        }
        let episodesBySeriesID = grouped

        let inProgressMovies = movies
            .filter {
                guard let percent = $0.userData?.playedPercentage else { return false }
                return percent > 0 && percent < 85
            }
            .sorted {
                ($0.userData?.lastPlayedDate ?? .distantPast) > ($1.userData?.lastPlayedDate ?? .distantPast)
            }
        let topWatchedMovies = Array(
            inProgressMovies.sorted {
                let a = (($0.userData?.playedPercentage ?? 0) / 100.0) * Double($0.runTimeTicks ?? 0)
                let b = (($1.userData?.playedPercentage ?? 0) / 100.0) * Double($1.runTimeTicks ?? 0)
                return a > b
            }.prefix(6)
        )

        // Precompute carousel items in background thread
        let showLookup = Dictionary(tvShows.compactMap { show in show.id.map { ($0, show) } }, uniquingKeysWith: { first, _ in first })
        let lookup: (String) -> BaseItemDto? = { showLookup[$0] }

        var pool: [BaseItemDto] = []
        var poolSeenIDs = Set<String>()
        for movie in movies {
            guard movie.type != .series else { continue }
            if movie.hasImageWithTitle(seriesLookup: lookup), let id = movie.id, !poolSeenIDs.contains(id) {
                poolSeenIDs.insert(id)
                pool.append(movie)
            }
        }
        var resumeBySeriesID: [String: BaseItemDto] = [:]
        for ep in resumeShows {
            if let sID = ep.seriesID, resumeBySeriesID[sID] == nil {
                resumeBySeriesID[sID] = ep
            }
        }
        for show in tvShows {
            guard let showID = show.id else { continue }
            if let episode = resumeBySeriesID[showID] ?? episodesBySeriesID[showID]?.first {
                guard episode.type != .series else { continue }
                if episode.hasImageWithTitle(seriesLookup: lookup), let id = episode.id, !poolSeenIDs.contains(id) {
                    poolSeenIDs.insert(id)
                    pool.append(episode)
                }
            }
        }

        var distinctIDsWithTitle = Set(pool.compactMap(\.id))
        for item in topWatchedMovies + resumeShows {
            guard item.type != .series else { continue }
            if item.hasImageWithTitle(seriesLookup: lookup) {
                if let id = item.id { distinctIDsWithTitle.insert(id) }
            }
        }

        var carouselItems: [BaseItemDto] = []
        if distinctIDsWithTitle.count >= 6 {
            var seenIDs = Set<String>()
            for movie in topWatchedMovies {
                guard carouselItems.count < 6 else { break }
                guard movie.type != .series, movie.hasImageWithTitle(seriesLookup: lookup) else { continue }
                if let id = movie.id, !seenIDs.contains(id) {
                    seenIDs.insert(id)
                    carouselItems.append(movie)
                }
            }
            for show in resumeShows {
                guard carouselItems.count < 6 else { break }
                guard show.type != .series, show.hasImageWithTitle(seriesLookup: lookup) else { continue }
                if let id = show.id, !seenIDs.contains(id) {
                    seenIDs.insert(id)
                    carouselItems.append(show)
                }
            }
            if carouselItems.count < 6 {
                for item in pool.shuffled() {
                    guard carouselItems.count < 6 else { break }
                    guard item.type != .series, item.hasImageWithTitle(seriesLookup: lookup) else { continue }
                    if let id = item.id, !seenIDs.contains(id) {
                        seenIDs.insert(id)
                        carouselItems.append(item)
                    }
                }
            }
        }

        // Precompute genres in background thread
        var genreCounts: [String: Int] = [:]
        for item in (movies + tvShows) {
            for genre in item.genres ?? [] {
                genreCounts[genre, default: 0] += 1
            }
        }
        let genres = genreCounts
            .map { GenreCount(name: $0.key, count: $0.value) }
            .sorted { lhs, rhs in
                lhs.count != rhs.count ? lhs.count > rhs.count : lhs.name < rhs.name
            }

        let completedCount = movies.filter { $0.userData?.isPlayed == true }.count
        let watchedHours = Int(
            movies.reduce(0.0) { acc, item in
                guard let ticks = item.runTimeTicks,
                      let percent = item.userData?.playedPercentage, percent > 0 else { return acc }
                return acc + (percent / 100.0) * Double(ticks) / 10_000_000
            } / 3_600
        )

        return LibraryDataSnapshot(
            itemsByID: newItemsByID,
            movieIDs: recordedMovieIDs,
            tvShowIDs: recordedShowIDs,
            episodeIDs: recordedEpisodeIDs,
            collectionIDs: recordedCollectionIDs,
            recommendedIDs: recordedRecommendedIDs,
            recentlyAddedMovieIDs: recordedRecentMovieIDs,
            recentlyAddedShowIDs: recordedRecentShowIDs,
            recentlyAddedIDs: recordedRecentIDs,
            resumeShowIDs: recordedNextUpIDs,
            favoritesCount: fetchedFavorites,
            tvSeriesCount: fetchedShows.count,
            episodeCount: fetchedEpisodes.count > 0 ? fetchedEpisodes.count : fetchedEpisodeCount,
            movies: movies,
            tvShows: tvShows,
            episodes: episodes,
            collections: collections,
            recommended: recommended,
            recentlyAddedMovies: recentlyAddedMovies,
            recentlyAddedShows: recentlyAddedShows,
            recentlyAdded: recentlyAdded,
            resumeShows: resumeShows,
            episodesBySeriesID: episodesBySeriesID,
            inProgressMovies: inProgressMovies,
            topWatchedMovies: topWatchedMovies,
            carouselItems: carouselItems,
            genres: genres,
            completedCount: completedCount,
            watchedHours: watchedHours
        )
    }

    private func apply(_ snapshot: LibraryDataSnapshot) {
        itemsByID             = snapshot.itemsByID
        movieIDs              = snapshot.movieIDs
        tvShowIDs             = snapshot.tvShowIDs
        episodeIDs            = snapshot.episodeIDs
        collectionIDs         = snapshot.collectionIDs
        recommendedIDs        = snapshot.recommendedIDs
        recentlyAddedMovieIDs = snapshot.recentlyAddedMovieIDs
        recentlyAddedShowIDs  = snapshot.recentlyAddedShowIDs
        recentlyAddedIDs      = snapshot.recentlyAddedIDs
        resumeShowIDs         = snapshot.resumeShowIDs
        favoritesCount        = snapshot.favoritesCount
        tvSeriesCount         = snapshot.tvSeriesCount
        episodeCount          = snapshot.episodeCount

        movies                = snapshot.movies
        tvShows               = snapshot.tvShows
        episodes              = snapshot.episodes
        collections           = snapshot.collections
        recommended           = snapshot.recommended
        recentlyAddedMovies   = snapshot.recentlyAddedMovies
        recentlyAddedShows    = snapshot.recentlyAddedShows
        recentlyAdded         = snapshot.recentlyAdded
        resumeShows           = snapshot.resumeShows
        episodesBySeriesID    = snapshot.episodesBySeriesID
        inProgressMovies      = snapshot.inProgressMovies
        topWatchedMovies      = snapshot.topWatchedMovies
        carouselItems         = snapshot.carouselItems
        genres                = snapshot.genres
        completedCount        = snapshot.completedCount
        watchedHours          = snapshot.watchedHours
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
        updateAggregates()
    }

    // MARK: - Aggregates

    private func updateAggregates() {
        movies = movieIDs.compactMap { itemsByID[$0] }
        tvShows = tvShowIDs.compactMap { itemsByID[$0] }
        episodes = episodeIDs.compactMap { itemsByID[$0] }
        collections = collectionIDs.compactMap { itemsByID[$0] }
        recommended = recommendedIDs.compactMap { itemsByID[$0] }
        recentlyAddedMovies = recentlyAddedMovieIDs.compactMap { itemsByID[$0] }
        recentlyAddedShows = recentlyAddedShowIDs.compactMap { itemsByID[$0] }
        recentlyAdded = recentlyAddedIDs.compactMap { itemsByID[$0] }
        resumeShows = resumeShowIDs.compactMap { itemsByID[$0] }.filter { !$0.isUnplayedFirstEpisode }

        var grouped: [String: [BaseItemDto]] = [:]
        for ep in episodes {
            if let seriesID = ep.seriesID {
                grouped[seriesID, default: []].append(ep)
            }
        }
        episodesBySeriesID = grouped

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

    // MARK: - Prefetching

    func prefetchBackdrops(around index: Int, items: [BaseItemDto]? = nil, client: JellyfinClient) {
        let targetItems = items ?? movies
        let neighbors = [index - 1, index, index + 1]
            .filter { $0 >= 0 && $0 < targetItems.count }
        let urls = neighbors.compactMap { targetItems[$0].backdropURL(client: client) }
        SDWebImagePrefetcher.shared.prefetchURLs(urls)
    }

    func prefetchPosters(around index: Int, client: JellyfinClient) {
        let neighbors = [index - 1, index, index + 1]
            .filter { $0 >= 0 && $0 < movies.count }
        let urls = neighbors.compactMap { movies[$0].posterURL(client: client) }
        SDWebImagePrefetcher.shared.prefetchURLs(urls)
    }
}
