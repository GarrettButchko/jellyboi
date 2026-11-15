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


/// Owns all of the media fetched from the server. Items are fetched once with card-level
/// metadata into `itemsByID`. All library categories, rows, and views operate on IDs only.
@Observable
@MainActor
class LibraryViewModel {

    // MARK: - Normalized store (Single Source of Truth)

    private(set) var itemsByID: [String: BaseItemDto] = [:]

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
    private(set) var carouselItemIDs: [String] = []
    private(set) var genres: [GenreCount] = []
    private(set) var episodesBySeriesID: [String: [String]] = [:]

    // MARK: - Lookup & Store Helpers

    func item(for itemID: String) -> BaseItemDto? {
        itemsByID[itemID]
    }

    subscript(itemID: String) -> BaseItemDto? {
        itemsByID[itemID]
    }

    func episodes(forSeriesID seriesID: String) -> [BaseItemDto] {
        (episodesBySeriesID[seriesID] ?? []).compactMap { itemsByID[$0] }
    }

    
    // MARK: - Stats Collections for Results View (IDs)
    var inProgressMovieIDs: [String] {
        movieIDs
            .filter { id in
                guard let percent = itemsByID[id]?.userData?.playedPercentage else { return false }
                return percent > 0 && percent < 85
            }
            .sorted {
                let a = itemsByID[$0]?.userData?.lastPlayedDate ?? .distantPast
                let b = itemsByID[$1]?.userData?.lastPlayedDate ?? .distantPast
                return a > b
            }
    }

    var topWatchedMovieIDs: [String] {
        Array(
            inProgressMovieIDs.sorted {
                let aItem = itemsByID[$0]
                let bItem = itemsByID[$1]
                let a = ((aItem?.userData?.playedPercentage ?? 0) / 100.0) * Double(aItem?.runTimeTicks ?? 0)
                let b = ((bItem?.userData?.playedPercentage ?? 0) / 100.0) * Double(bItem?.runTimeTicks ?? 0)
                return a > b
            }.prefix(6)
        )
    }
    
    var favoriteIDs: [String] {
        let favMovies = movieIDs.filter { itemsByID[$0]?.userData?.isFavorite == true }
        let favShows = tvShowIDs.filter { itemsByID[$0]?.userData?.isFavorite == true }
        let starredShowIDs = Set(favShows)
        let favEpisodes = episodeIDs.filter { id in
            guard let ep = itemsByID[id], ep.userData?.isFavorite == true else { return false }
            let showID = ep.seriesID ?? ep.parentBackdropItemID
            if let showID, starredShowIDs.contains(showID) {
                return false
            }
            return true
        }
        return (favMovies + favShows + favEpisodes).sorted { lhs, rhs in
            let a = itemsByID[lhs]?.sortName ?? itemsByID[lhs]?.name ?? ""
            let b = itemsByID[rhs]?.sortName ?? itemsByID[rhs]?.name ?? ""
            return a < b
        }
    }
    
    var completedMovieIDs: [String] {
        movieIDs
            .filter { itemsByID[$0]?.userData?.isPlayed == true }
            .sorted {
                let a = itemsByID[$0]?.userData?.lastPlayedDate ?? .distantPast
                let b = itemsByID[$1]?.userData?.lastPlayedDate ?? .distantPast
                return a > b
            }
    }

    var watchedMovieIDs: [String] {
        movieIDs
            .filter {
                guard let item = itemsByID[$0] else { return false }
                return (item.userData?.playedPercentage ?? 0) > 0 || item.userData?.isPlayed == true
            }
            .sorted {
                let a = itemsByID[$0]?.userData?.lastPlayedDate ?? .distantPast
                let b = itemsByID[$1]?.userData?.lastPlayedDate ?? .distantPast
                return a > b
            }
    }
    
    // MARK: - Home Aggregates & Computed Stats (ID-Based)

    var completedCount: Int {
        movieIDs.reduce(0) { count, id in
            itemsByID[id]?.userData?.isPlayed == true ? count + 1 : count
        }
    }

    var watchedHours: Int {
        let total = movieIDs.reduce(0.0) { acc, id in
            guard let item = itemsByID[id],
                  let ticks = item.runTimeTicks,
                  let percent = item.userData?.playedPercentage, percent > 0 else { return acc }
            return acc + (percent / 100.0) * Double(ticks) / 10_000_000
        }
        return Int(total / 3_600)
    }


    // MARK: - Lifecycle & State

    @ObservationIgnored
    private var currentUserID: String?
    @ObservationIgnored
    private var currentClient: JellyfinClient?

    private(set) var isLoading = false
    var errorMessage: String?

    var isLibraryEmpty: Bool { movieIDs.isEmpty && tvShowIDs.isEmpty && episodeIDs.isEmpty }

    func load(using client: JellyfinClient, userID: String? = nil) async {
        self.currentClient = client
        if let userID {
            self.currentUserID = userID
        }
        guard isLibraryEmpty else { return }
        guard !isLoading else { return }
        await refresh(using: client, userID: userID ?? currentUserID)
    }

    func refresh(using client: JellyfinClient, userID: String? = nil) async {
        self.currentClient = client
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        if let userID {
            self.currentUserID = userID
        }
        let effectiveUserID = userID ?? currentUserID

        do {
            let snapshot = try await Self.fetchLibraryData(using: client, userID: effectiveUserID)
            apply(snapshot)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - User Data & Playback Updates

    func applyUserData(_ dtos: [UserItemDataDto]) {
        var changedIDs = Set<String>()

        for dto in dtos {
            let itemID = dto.itemID ?? dto.key
            guard var item = itemsByID[itemID] else { continue }
            item.userData = dto
            itemsByID[itemID] = item
            changedIDs.insert(itemID)
        }

        guard !changedIDs.isEmpty else { return }

        resumeShowIDs.removeAll { id in
            guard changedIDs.contains(id) else { return false }
            guard let item = itemsByID[id] else { return true }
            return !item.hasProgress && !item.isWatched
        }
    }

    func updateProgress(for itemID: String, positionTicks: Int, totalTicks: Int?) {
        if var item = itemsByID[itemID] {
            item.updateProgress(positionTicks: positionTicks, totalTicks: totalTicks)
            itemsByID[itemID] = item
        }
    }

    // MARK: - Internal Data Fetching & Processing Pipeline

    private struct FetchedLibraryData: Sendable {
        let movies: [BaseItemDto]
        let tvShows: [BaseItemDto]
        let episodes: [BaseItemDto]
        let collections: [BaseItemDto]
        let recommendedIDs: [String]
        let recentMovieIDs: [String]
        let recentShowIDs: [String]
        let nextUpIDs: [String]
    }

    private nonisolated static func fetchLibraryData(
        using client: JellyfinClient,
        userID: String?
    ) async throws -> FetchedLibraryData {
        let moviesParams = Paths.GetItemsParameters.movies(userID: userID)
        let showsParams = Paths.GetItemsParameters.tvShows(userID: userID)
        let episodesParams = Paths.GetItemsParameters.episodes(userID: userID)
        let collectionsParams = Paths.GetItemsParameters.collections(userID: userID)
        let recommendedParams = Paths.GetItemsParameters.recommended(userID: userID)
        let recentMoviesParams = Paths.GetItemsParameters.recentMovies(userID: userID)
        let recentShowsParams = Paths.GetItemsParameters.recentShows(userID: userID)
        let nextUpParams = Paths.GetNextUpParameters.standard(userID: userID, limit: 20)

        async let moviesResponse       = client.send(Paths.getItems(parameters: moviesParams))
        async let showsResponse        = client.send(Paths.getItems(parameters: showsParams))
        async let episodesResponse     = try? client.send(Paths.getItems(parameters: episodesParams))
        async let collectionsResponse  = try? client.send(Paths.getItems(parameters: collectionsParams))
        async let recommendedResponse  = try? client.send(Paths.getItems(parameters: recommendedParams))
        async let recentMoviesResponse = try? client.send(Paths.getItems(parameters: recentMoviesParams))
        async let recentShowsResponse  = try? client.send(Paths.getItems(parameters: recentShowsParams))
        async let nextUpResponse       = try? client.send(Paths.getNextUp(parameters: nextUpParams))

        let fetchedMovies        = (try await moviesResponse).value.items ?? []
        let fetchedShows         = (try await showsResponse).value.items ?? []
        let fetchedEpisodes      = (await episodesResponse)?.value.items ?? []
        let fetchedCollections   = (await collectionsResponse)?.value.items ?? []
        let fetchedRecommendedIDs = (await recommendedResponse)?.value.items?.compactMap(\.id) ?? []
        let fetchedRecentMovieIDs = (await recentMoviesResponse)?.value.items?.compactMap(\.id) ?? []
        let fetchedRecentShowIDs  = (await recentShowsResponse)?.value.items?.compactMap(\.id) ?? []
        let fetchedNextUpIDs      = (await nextUpResponse)?.value.items?.compactMap(\.id) ?? []

        return FetchedLibraryData(
            movies: fetchedMovies,
            tvShows: fetchedShows,
            episodes: fetchedEpisodes,
            collections: fetchedCollections,
            recommendedIDs: fetchedRecommendedIDs,
            recentMovieIDs: fetchedRecentMovieIDs,
            recentShowIDs: fetchedRecentShowIDs,
            nextUpIDs: fetchedNextUpIDs,
        )
    }
    
    private func apply(_ snapshot: FetchedLibraryData) {
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

        let recordedMovieIDs      = record(snapshot.movies)
        let recordedShowIDs       = record(snapshot.tvShows)
        let recordedEpisodeIDs    = record(snapshot.episodes)
        let recordedCollectionIDs = record(snapshot.collections)

        var groupedEpisodes: [String: [String]] = [:]
        for episode in snapshot.episodes {
            guard let epID = episode.id, let seriesID = episode.seriesID else { continue }
            groupedEpisodes[seriesID, default: []].append(epID)
        }

        var seenRecentIDs = Set<String>()
        var uniqueRecentIDs: [String] = []
        for id in snapshot.recentMovieIDs + snapshot.recentShowIDs {
            if seenRecentIDs.insert(id).inserted {
                uniqueRecentIDs.append(id)
            }
        }
        let sortedRecentIDs = uniqueRecentIDs.sorted { id1, id2 in
            let date1 = newItemsByID[id1]?.dateCreated ?? .distantPast
            let date2 = newItemsByID[id2]?.dateCreated ?? .distantPast
            return date1 > date2
        }

        let filteredResumeIDs = snapshot.nextUpIDs.filter { id in
            guard let item = newItemsByID[id] else { return true }
            return !item.isUnplayedFirstEpisode
        }

        itemsByID             = newItemsByID
        movieIDs              = recordedMovieIDs
        tvShowIDs             = recordedShowIDs
        episodeIDs            = recordedEpisodeIDs
        collectionIDs         = recordedCollectionIDs
        recommendedIDs        = snapshot.recommendedIDs
        recentlyAddedMovieIDs = snapshot.recentMovieIDs
        recentlyAddedShowIDs  = snapshot.recentShowIDs
        recentlyAddedIDs      = sortedRecentIDs
        resumeShowIDs         = filteredResumeIDs
        episodesBySeriesID    = groupedEpisodes
        genres                = Self.computeGenres(
            movieIDs: recordedMovieIDs,
            tvShowIDs: recordedShowIDs,
            itemsByID: newItemsByID
        )
        carouselItemIDs       = Self.computeCarouselItemIDs(
            movieIDs: recordedMovieIDs,
            tvShowIDs: recordedShowIDs,
            resumeShowIDs: filteredResumeIDs,
            episodesBySeriesID: groupedEpisodes,
            topWatchedMovieIDs: topWatchedMovieIDs,
            itemsByID: newItemsByID
        )
    }

    private static func computeCarouselItemIDs(
        movieIDs: [String],
        tvShowIDs: [String],
        resumeShowIDs: [String],
        episodesBySeriesID: [String: [String]],
        topWatchedMovieIDs: [String],
        itemsByID: [String: BaseItemDto]
    ) -> [String] {
        let lookup: (String) -> BaseItemDto? = { itemsByID[$0] }

        var poolIDs: [String] = []
        var poolSeenIDs = Set<String>()

        for movieID in movieIDs {
            guard let movie = itemsByID[movieID], movie.type != .series else { continue }
            if movie.hasImageWithTitle(seriesLookup: lookup), !poolSeenIDs.contains(movieID) {
                poolSeenIDs.insert(movieID)
                poolIDs.append(movieID)
            }
        }

        var resumeBySeriesID: [String: String] = [:]
        for epID in resumeShowIDs {
            if let ep = itemsByID[epID], let sID = ep.seriesID, resumeBySeriesID[sID] == nil {
                resumeBySeriesID[sID] = epID
            }
        }

        for showID in tvShowIDs {
            if let epID = resumeBySeriesID[showID] ?? episodesBySeriesID[showID]?.first,
               let episode = itemsByID[epID], episode.type != .series {
                if episode.hasImageWithTitle(seriesLookup: lookup), !poolSeenIDs.contains(epID) {
                    poolSeenIDs.insert(epID)
                    poolIDs.append(epID)
                }
            }
        }

        var distinctIDsWithTitle = Set(poolIDs)
        for itemID in topWatchedMovieIDs + resumeShowIDs {
            guard let item = itemsByID[itemID], item.type != .series else { continue }
            if item.hasImageWithTitle(seriesLookup: lookup) {
                distinctIDsWithTitle.insert(itemID)
            }
        }

        var carouselItemIDs: [String] = []
        if distinctIDsWithTitle.count >= 6 {
            var seenIDs = Set<String>()
            for movieID in topWatchedMovieIDs {
                guard carouselItemIDs.count < 6 else { break }
                guard let movie = itemsByID[movieID], movie.type != .series, movie.hasImageWithTitle(seriesLookup: lookup) else { continue }
                if !seenIDs.contains(movieID) {
                    seenIDs.insert(movieID)
                    carouselItemIDs.append(movieID)
                }
            }
            for showID in resumeShowIDs {
                guard carouselItemIDs.count < 6 else { break }
                guard let show = itemsByID[showID], show.type != .series, show.hasImageWithTitle(seriesLookup: lookup) else { continue }
                if !seenIDs.contains(showID) {
                    seenIDs.insert(showID)
                    carouselItemIDs.append(showID)
                }
            }
            if carouselItemIDs.count < 6 {
                for poolID in poolIDs.shuffled() {
                    guard carouselItemIDs.count < 6 else { break }
                    guard let item = itemsByID[poolID], item.type != .series, item.hasImageWithTitle(seriesLookup: lookup) else { continue }
                    if !seenIDs.contains(poolID) {
                        seenIDs.insert(poolID)
                        carouselItemIDs.append(poolID)
                    }
                }
            }
        }
        return carouselItemIDs
    }

    private static func computeGenres(
        movieIDs: [String],
        tvShowIDs: [String],
        itemsByID: [String: BaseItemDto]
    ) -> [GenreCount] {
        var genreCounts: [String: Int] = [:]
        for id in (movieIDs + tvShowIDs) {
            guard let item = itemsByID[id] else { continue }
            for genre in item.genres ?? [] {
                genreCounts[genre, default: 0] += 1
            }
        }
        return genreCounts
            .map { GenreCount(name: $0.key, count: $0.value) }
            .sorted { lhs, rhs in
                lhs.count != rhs.count ? lhs.count > rhs.count : lhs.name < rhs.name
            }
    }

    // MARK: - Prefetching & Artwork

    func prefetchBackdrops(around index: Int, itemIDs: [String]? = nil, client: JellyfinClient) {
        let targetIDs = itemIDs ?? carouselItemIDs
        let neighbors = [index - 1, index, index + 1]
            .filter { $0 >= 0 && $0 < targetIDs.count }
        let urls = neighbors.compactMap { itemsByID[targetIDs[$0]]?.backdropURL(client: client) }
        SDWebImagePrefetcher.shared.prefetchURLs(urls)
    }

    func prefetchPosters(around index: Int, itemIDs: [String]? = nil, client: JellyfinClient) {
        let targetIDs = itemIDs ?? movieIDs
        let neighbors = [index - 1, index, index + 1]
            .filter { $0 >= 0 && $0 < targetIDs.count }
        let urls = neighbors.compactMap { itemsByID[targetIDs[$0]]?.posterURL(client: client) }
        SDWebImagePrefetcher.shared.prefetchURLs(urls)
    }

    func prefetchArtwork(client: JellyfinClient, maxCount: Int = 50) {
        var urls: [URL] = []
        for id in carouselItemIDs.prefix(10) {
            if let url = itemsByID[id]?.backdropURL(client: client) {
                urls.append(url)
            }
        }
        let cardIDs = movieIDs.prefix(maxCount) + tvShowIDs.prefix(maxCount) + collectionIDs.prefix(20)
        for id in cardIDs {
            if let url = itemsByID[id]?.posterURL(client: client) {
                urls.append(url)
            }
        }
        SDWebImagePrefetcher.shared.prefetchURLs(urls)
    }
}
