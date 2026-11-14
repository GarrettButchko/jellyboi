//
//  MediaViewModel.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 8/23/26.
//

import Foundation
import Observation
import Get
import JellyfinAPI

enum MediaFilter: CaseIterable, Hashable {
    case movies
    case tvShows

    var title: String {
        switch self {
        case .movies: "Movies"
        case .tvShows: "TV Shows"
        }
    }
}

/// The single section shown in the Media tab. Replaces the previous
/// filter + toggle pair so exactly one section can ever be active.
enum MediaScope: CaseIterable, Hashable {
    case movies
    case tvShows
    case favorites
    case downloads

    var title: String {
        switch self {
        case .movies: "Movies"
        case .tvShows: "TV Shows"
        case .favorites: "Favorites"
        case .downloads: "Downloads"
        }
    }

    var icon: String {
        switch self {
        case .movies: "film"
        case .tvShows: "tv"
        case .favorites: "star"
        case .downloads: "square.and.arrow.down"
        }
    }
}

/// One titled grid inside a scope such as Favorites or Downloads.
struct MediaSection: Identifiable {
    var id: String { title }
    let title: String
    let items: [BaseItemDto]
}

@Observable
@MainActor
class MediaViewModel {
    var scope: MediaScope = .movies
    var library = LibraryViewModel()

    init(library: LibraryViewModel? = nil) {
        if let library { self.library = library }
    }

    // MARK: - Regular Library Items

    var regularMovies: [BaseItemDto] {
        #if DEBUG
        if DebugSettings.shared.simulateMediaEmptyLibrary || DebugSettings.shared.hideMediaMovies { return [] }
        #endif
        return library.movies
    }

    var regularShows: [BaseItemDto] {
        #if DEBUG
        if DebugSettings.shared.simulateMediaEmptyLibrary || DebugSettings.shared.hideMediaShows { return [] }
        #endif
        return library.tvShows
    }

    // MARK: - Favorite Items

    var favoriteMovies: [BaseItemDto] {
        #if DEBUG
        if DebugSettings.shared.simulateMediaEmptyLibrary || DebugSettings.shared.hideMediaFavorites { return [] }
        #endif
        return library.movies.filter { $0.userData?.isFavorite == true }
    }

    var favoriteShows: [BaseItemDto] {
        #if DEBUG
        if DebugSettings.shared.simulateMediaEmptyLibrary || DebugSettings.shared.hideMediaFavorites { return [] }
        #endif
        return library.tvShows.filter { $0.userData?.isFavorite == true }
    }

    /// Only show favorite episodes if the whole show isn't starred.
    var favoriteEpisodes: [BaseItemDto] {
        #if DEBUG
        if DebugSettings.shared.simulateMediaEmptyLibrary || DebugSettings.shared.hideMediaFavorites { return [] }
        #endif
        let starredShowIDs = Set(favoriteShows.compactMap(\.id))
        return library.episodes.filter { ep in
            guard ep.userData?.isFavorite == true else { return false }
            let showID = ep.seriesID ?? ep.parentBackdropItemID
            if let showID, starredShowIDs.contains(showID) {
                return false
            }
            return true
        }
    }

    var favoriteCollections: [BaseItemDto] {
        #if DEBUG
        if DebugSettings.shared.simulateMediaEmptyLibrary || DebugSettings.shared.hideMediaFavorites { return [] }
        #endif
        return library.collections.filter { $0.userData?.isFavorite == true }
    }

    // MARK: - Download State & Filtering

    /// Determines if all episodes of a TV show are downloaded.
    func isShowFullyDownloaded(_ seriesID: String, downloadManager: DownloadManager) -> Bool {
        let episodesForShow = library.episodes.filter {
            ($0.seriesID ?? $0.parentBackdropItemID) == seriesID
        }
        if !episodesForShow.isEmpty {
            let completedIDs = Set(downloadManager.completedDownloads.compactMap(\.item.id))
            return episodesForShow.allSatisfy { ep in
                guard let id = ep.id else { return false }
                return completedIDs.contains(id)
            }
        }

        let showItem = library.tvShows.first(where: { $0.id == seriesID })
        let total = showItem?.recursiveItemCount ?? showItem?.childCount
        if let total, total > 0 {
            let downloadedCount = downloadManager.completedDownloads.filter {
                ($0.item.seriesID ?? $0.item.parentBackdropItemID) == seriesID
            }.count
            return downloadedCount >= total
        }

        if downloadManager.completedDownloads.contains(where: { $0.item.type == .series && $0.item.id == seriesID }) {
            return true
        }

        return false
    }

    /// Returns shows that are fully downloaded.
    func downloadedShows(downloadManager: DownloadManager) -> [BaseItemDto] {
        var candidateShowIDs = Set<String>()
        var showNames: [String: String] = [:]

        for download in downloadManager.completedDownloads {
            if download.item.type == .series, let id = download.item.id {
                candidateShowIDs.insert(id)
                if let name = download.item.name { showNames[id] = name }
            }
            if download.item.type == .episode || download.item.seriesName != nil {
                let showID = download.item.seriesID ?? download.item.parentBackdropItemID
                if let showID {
                    candidateShowIDs.insert(showID)
                    if let name = download.item.seriesName { showNames[showID] = name }
                }
            }
        }

        var results: [BaseItemDto] = []
        for showID in candidateShowIDs {
            if isShowFullyDownloaded(showID, downloadManager: downloadManager) {
                if let show = library.tvShows.first(where: { $0.id == showID }) {
                    results.append(show)
                } else {
                    results.append(BaseItemDto(
                        id: showID,
                        name: showNames[showID] ?? "Show",
                        type: .series
                    ))
                }
            }
        }
        return results.sorted { ($0.name ?? "") < ($1.name ?? "") }
    }

    /// Only returns downloaded episodes if their whole show isn't downloaded.
    /// Prefers the live library copy so artwork and metadata stay current.
    func downloadedEpisodes(downloadManager: DownloadManager) -> [BaseItemDto] {
        downloadManager.completedDownloads
            .map(\.item)
            .filter { item in
                guard item.type == .episode || item.seriesName != nil else { return false }
                guard let showID = item.seriesID ?? item.parentBackdropItemID else { return true }
                return !isShowFullyDownloaded(showID, downloadManager: downloadManager)
            }
            .map(liveLibraryItem)
    }

    /// Returns downloaded movies, preferring the live library copy.
    func downloadedMovies(downloadManager: DownloadManager) -> [BaseItemDto] {
        downloadManager.downloadedMovies.map(liveLibraryItem)
    }

    /// The library's copy of a downloaded item, when it still exists.
    private func liveLibraryItem(_ item: BaseItemDto) -> BaseItemDto {
        guard let id = item.id, let liveItem = library.item(for: id) else { return item }
        return liveItem
    }

    // MARK: - Sections

    /// Favorited collections, shows, episodes, and movies. Empty sections are dropped.
    var favoriteSections: [MediaSection] {
        [
            MediaSection(title: "Collections", items: favoriteCollections),
            MediaSection(title: "TV Shows", items: favoriteShows),
            MediaSection(title: "Episodes", items: favoriteEpisodes),
            MediaSection(title: "Movies", items: favoriteMovies),
        ]
        .filter { !$0.items.isEmpty }
    }

    /// Fully downloaded shows plus any individually downloaded episodes and movies.
    func downloadSections(downloadManager: DownloadManager) -> [MediaSection] {
        [
            MediaSection(title: "TV Shows", items: downloadedShows(downloadManager: downloadManager)),
            MediaSection(title: "Episodes", items: downloadedEpisodes(downloadManager: downloadManager)),
            MediaSection(title: "Movies", items: downloadedMovies(downloadManager: downloadManager)),
        ]
        .filter { !$0.items.isEmpty }
    }

    // MARK: - Scope Availability

    /// Movies and TV Shows are always offered. Favorites and Downloads only
    /// appear once something has actually been favorited or downloaded.
    func availableScopes(downloadManager: DownloadManager) -> [MediaScope] {
        var scopes: [MediaScope] = [.movies, .tvShows]
        if !favoriteSections.isEmpty {
            scopes.append(.favorites)
        }
        if !downloadSections(downloadManager: downloadManager).isEmpty {
            scopes.append(.downloads)
        }
        return scopes
    }

    /// Number of items the scope would show, used for the menu badges.
    func scopeCount(_ scope: MediaScope, downloadManager: DownloadManager) -> Int {
        switch scope {
        case .movies:
            return regularMovies.count
        case .tvShows:
            return regularShows.count
        case .favorites:
            return favoriteSections.reduce(0) { $0 + $1.items.count }
        case .downloads:
            return downloadSections(downloadManager: downloadManager).reduce(0) { $0 + $1.items.count }
        }
    }

    // MARK: - Loading & Errors

    var isLoading: Bool { library.isLoading }
    var errorMessage: String? {
        #if DEBUG
        if DebugSettings.shared.simulateMediaError { return "Debug: Simulated media library error" }
        #endif
        return library.errorMessage
    }

    func refresh(using client: JellyfinClient) async {
        await library.refresh(using: client)
    }

    func refreshMediaArtwork(using client: JellyfinClient? = nil) async {
        await library.refreshMediaArtwork(using: client)
    }

    func refreshArtwork(using client: JellyfinClient? = nil) async {
        await library.refreshArtwork(using: client)
    }
}
