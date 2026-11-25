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

    static let shared = LibraryViewModel()

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
    
    // stores episode ids with their series id as key
    private(set) var episodesBySeriesID: [String: [String]] = [:]

    // MARK: - Lookup & Store Helpers

    subscript(itemID: String) -> BaseItemDto? {
        get {
            itemsByID[itemID]
        }
        set {
            itemsByID[itemID] = newValue
        }
    }

    func item(for itemID: String) -> BaseItemDto? {
        self[itemID]
    }

    func episodeItems(forSeriesID seriesID: String) -> [BaseItemDto] {
        return (episodesBySeriesID[seriesID] ?? []).compactMap { self[$0] }
    }

    func episodes(forSeriesID seriesID: String) -> [BaseItemDto] {
        episodeItems(forSeriesID: seriesID)
    }

    func parentSeriesId(childId id: String?) -> String? {
        guard let id, let item = self[id] else { return nil }
        return parentSeriesId(for: item)
    }

    func parentSeriesId(for item: BaseItemDto?) -> String? {
        guard let seriesID = item?.seriesID, let found = self[seriesID] else { return nil }
        return found.id
    }
    
    func parentSeriesItem(childId id: String?) -> BaseItemDto? {
        guard let id, let item = self[id] else { return nil }
        return parentSeriesItem(for: item)
    }

    func parentSeriesItem(for item: BaseItemDto?) -> BaseItemDto? {
        guard let seriesID = item?.seriesID else { return nil }
        return self[seriesID]
    }

    func parentSeries(childId id: String?) -> BaseItemDto? {
        parentSeriesItem(childId: id)
    }

    func parentSeries(for item: BaseItemDto?) -> BaseItemDto? {
        parentSeriesItem(for: item)
    }

    var tvSeriesCount: Int { tvShowIDs.count }
    var episodeCount: Int { episodeIDs.count }
    var favoritesCount: Int { favoriteIDs.count }

    // MARK: - Stats Collections for Results View (IDs)
    var inProgressMovieIDs: [String] {
        movieIDs
            .filter { id in
                guard let percent = self[id]?.userData?.playedPercentage else { return false }
                return percent > 0 && percent < 85
            }
            .sorted {
                let a = self[$0]?.userData?.lastPlayedDate ?? .distantPast
                let b = self[$1]?.userData?.lastPlayedDate ?? .distantPast
                return a > b
            }
    }

    var topWatchedMovieIDs: [String] {
        Array(
            inProgressMovieIDs.sorted {
                let aItem = self[$0]
                let bItem = self[$1]
                let a = ((aItem?.userData?.playedPercentage ?? 0) / 100.0) * Double(aItem?.runTimeTicks ?? 0)
                let b = ((bItem?.userData?.playedPercentage ?? 0) / 100.0) * Double(bItem?.runTimeTicks ?? 0)
                return a > b
            }.prefix(6)
        )
    }
    
    var favoriteIDs: [String] {
        let favMovies = movieIDs.filter { self[$0]?.userData?.isFavorite == true }
        let favShows = tvShowIDs.filter { self[$0]?.userData?.isFavorite == true }
        let starredShowIDs = Set(favShows)
        let favEpisodes = episodeIDs.filter { id in
            guard let ep = self[id], ep.userData?.isFavorite == true else { return false }
            let showID = parentSeriesId(for: ep) ?? ep.parentBackdropItemID
            if let showID, starredShowIDs.contains(showID) {
                return false
            }
            return true
        }
        return (favMovies + favShows + favEpisodes).sorted { lhs, rhs in
            let a = self[lhs]?.sortName ?? self[lhs]?.name ?? ""
            let b = self[rhs]?.sortName ?? self[rhs]?.name ?? ""
            return a < b
        }
    }
    
    var completedMovieIDs: [String] {
        movieIDs
            .filter { self[$0]?.userData?.isPlayed == true }
            .sorted {
                let a = self[$0]?.userData?.lastPlayedDate ?? .distantPast
                let b = self[$1]?.userData?.lastPlayedDate ?? .distantPast
                return a > b
            }
    }

    var watchedMovieIDs: [String] {
        movieIDs
            .filter {
                guard let item = self[$0] else { return false }
                return (item.userData?.playedPercentage ?? 0) > 0 || item.userData?.isPlayed == true
            }
            .sorted {
                let a = self[$0]?.userData?.lastPlayedDate ?? .distantPast
                let b = self[$1]?.userData?.lastPlayedDate ?? .distantPast
                return a > b
            }
    }
    
    // MARK: - Home Aggregates & Computed Stats (ID-Based)

    var completedCount: Int {
        movieIDs.reduce(0) { count, id in
            self[id]?.userData?.isPlayed == true ? count + 1 : count
        }
    }

    var watchedHours: Int {
        let total = movieIDs.reduce(0.0) { acc, id in
            guard let item = self[id],
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
    @ObservationIgnored
    private var userDataTask: Task<Void, Never>?
    @ObservationIgnored
    private var progressUpdateTask: Task<Void, Never>?

    init() {
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
                self.updateProgress(for: itemID, positionTicks: positionTicks, totalTicks: totalTicks)
            }
        }
    }

    deinit {
        userDataTask?.cancel()
        progressUpdateTask?.cancel()
    }

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
            guard var item = self[itemID] else { continue }
            item.userData = dto
            self[itemID] = item
            changedIDs.insert(itemID)
        }

        guard !changedIDs.isEmpty else { return }

        resumeShowIDs.removeAll { id in
            guard changedIDs.contains(id) else { return false }
            guard let item = self[id] else { return true }
            return (!item.hasProgress && !item.isWatched) || item.isWatched
        }

        for id in changedIDs {
            guard let item = self[id],
                  item.type == .episode,
                  item.isInProgress,
                  !resumeShowIDs.contains(id) else { continue }
            let seriesID = item.seriesID
            if let seriesID {
                resumeShowIDs.removeAll { self[$0]?.seriesID == seriesID }
            }
            resumeShowIDs.insert(id, at: 0)
        }
    }

    func updateProgress(for itemID: String, positionTicks: Int, totalTicks: Int?) {
        guard var item = self[itemID] else { return }
        item.updateProgress(positionTicks: positionTicks, totalTicks: totalTicks)
        self[itemID] = item

        guard item.type == .episode else { return }
        let seriesID = item.seriesID

        if item.isInProgress {
            resumeShowIDs.removeAll { existingID in
                existingID == itemID || (seriesID != nil && self[existingID]?.seriesID == seriesID)
            }
            resumeShowIDs.insert(itemID, at: 0)
        } else if item.isWatched {
            resumeShowIDs.removeAll { $0 == itemID }
        }
    }

    /// Refreshes the "Next Up" / continue-watching episode queue from the server.
    func refreshNextUp() async {
        guard let client = currentClient else { return }
        let params = Paths.GetNextUpParameters.standard(userID: currentUserID, limit: 20)
        guard let response = try? await client.send(Paths.getNextUp(parameters: params)) else { return }
        let nextUpItems = response.value.items ?? []

        for nextUpItem in nextUpItems {
            guard let id = nextUpItem.id else { continue }
            if var existing = self[id] {
                if let userData = nextUpItem.userData {
                    existing.userData = userData
                    self[id] = existing
                }
            } else {
                self[id] = nextUpItem
            }
        }

        let filteredNextUpIDs = nextUpItems.compactMap(\.id).filter { id in
            guard let item = self[id] else { return true }
            return !item.isUnplayedFirstEpisode
        }

        if filteredNextUpIDs != resumeShowIDs {
            resumeShowIDs = filteredNextUpIDs
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
        let urls: [URL] = neighbors.compactMap { idx -> URL? in
            guard let item = self[targetIDs[idx]] else { return nil }
            let lookup: (String) -> BaseItemDto? = { [weak self] id in self?.item(for: id) }
            return item.imageWithTitleURL(client: client, seriesLookup: lookup)
                ?? item.backdropURL(client: client)
        }
        CarouselImageMemoryCache.shared.preloadImages(for: urls)
    }

    func refreshMediaArtwork(using client: JellyfinClient? = nil, userID: String? = nil) async {
        guard let client = client ?? currentClient else { return }
        prefetchArtwork(client: client)
    }

    func prefetchPosters(around index: Int, itemIDs: [String]? = nil, client: JellyfinClient) {
        let targetIDs = itemIDs ?? movieIDs
        let neighbors = [index - 1, index, index + 1]
            .filter { $0 >= 0 && $0 < targetIDs.count }
        let urls: [URL] = neighbors.compactMap { idx -> URL? in
            self[targetIDs[idx]]?.posterURL(client: client)
        }
        SDWebImagePrefetcher.shared.prefetchURLs(urls)
    }

    func prefetchArtwork(client: JellyfinClient, maxCount: Int = 50) {
        var backdropURLs: [URL] = []
        let lookup: (String) -> BaseItemDto? = { [weak self] id in self?.item(for: id) }
        for id in carouselItemIDs.prefix(10) {
            guard let item = self[id] else { continue }
            if let url = item.imageWithTitleURL(client: client, seriesLookup: lookup)
                ?? item.backdropURL(client: client) {
                backdropURLs.append(url)
            }
        }
        if !backdropURLs.isEmpty {
            CarouselImageMemoryCache.shared.preloadImages(for: backdropURLs)
        }

        var posterURLs: [URL] = []
        let cardIDs = movieIDs.prefix(maxCount) + tvShowIDs.prefix(maxCount) + collectionIDs.prefix(20)
        for id in cardIDs {
            if let url = self[id]?.posterURL(client: client) {
                posterURLs.append(url)
            }
        }
        if !posterURLs.isEmpty {
            SDWebImagePrefetcher.shared.prefetchURLs(posterURLs)
        }
    }
}
