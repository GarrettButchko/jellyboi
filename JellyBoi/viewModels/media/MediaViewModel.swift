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
    let itemIDs: [String]
}

@Observable
@MainActor
class MediaViewModel {
    var scope: MediaScope = .movies
    var library = LibraryViewModel.shared

    init() {
        self.library = .shared
    }

    // MARK: - Regular Library Items (IDs)

    var regularMovieIDs: [String] {
        #if DEBUG
        if DebugSettings.shared.simulateMediaEmptyLibrary || DebugSettings.shared.hideMediaMovies { return [] }
        #endif
        return library.movieIDs
    }

    var regularShowIDs: [String] {
        #if DEBUG
        if DebugSettings.shared.simulateMediaEmptyLibrary || DebugSettings.shared.hideMediaShows { return [] }
        #endif
        return library.tvShowIDs
    }

    // MARK: - Favorite Items (IDs)

    var favoriteMovieIDs: [String] {
        #if DEBUG
        if DebugSettings.shared.simulateMediaEmptyLibrary || DebugSettings.shared.hideMediaFavorites { return [] }
        #endif
        return library.movieIDs.filter { library.item(for: $0)?.userData?.isFavorite == true }
    }

    var favoriteShowIDs: [String] {
        #if DEBUG
        if DebugSettings.shared.simulateMediaEmptyLibrary || DebugSettings.shared.hideMediaFavorites { return [] }
        #endif
        return library.tvShowIDs.filter { library.item(for: $0)?.userData?.isFavorite == true }
    }

    /// Only show favorite episodes if the whole show isn't starred.
    var favoriteEpisodeIDs: [String] {
        #if DEBUG
        if DebugSettings.shared.simulateMediaEmptyLibrary || DebugSettings.shared.hideMediaFavorites { return [] }
        #endif
        let starredShowIDs = Set(favoriteShowIDs)
        return library.episodeIDs.filter { epID in
            guard let ep = library.item(for: epID), ep.userData?.isFavorite == true else { return false }
            let showID = library.parentSeriesId(for: ep) ?? ep.parentBackdropItemID
            if let showID, starredShowIDs.contains(showID) {
                return false
            }
            return true
        }
    }

    var favoriteCollectionIDs: [String] {
        #if DEBUG
        if DebugSettings.shared.simulateMediaEmptyLibrary || DebugSettings.shared.hideMediaFavorites { return [] }
        #endif
        return library.collectionIDs.filter { library.item(for: $0)?.userData?.isFavorite == true }
    }

    // MARK: - Download State & Filtering

    /// Determines if all episodes of a TV show are downloaded.
    func isShowFullyDownloaded(_ seriesID: String, downloadManager: DownloadManager) -> Bool {
        let episodesForShow = library.episodes(forSeriesID: seriesID)
        if !episodesForShow.isEmpty {
            let completedIDs = Set(downloadManager.completedDownloads.compactMap(\.item.id))
            return episodesForShow.allSatisfy { ep in
                guard let id = ep.id else { return false }
                return completedIDs.contains(id)
            }
        }

        let showItem = library.item(for: seriesID)
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

    /// Returns show IDs that are fully downloaded.
    func downloadedShowIDs(downloadManager: DownloadManager) -> [String] {
        var candidateShowIDs = Set<String>()

        for download in downloadManager.completedDownloads {
            if download.item.type == .series, let id = download.item.id {
                candidateShowIDs.insert(id)
            }
            if download.item.type == .episode || download.item.seriesName != nil {
                let showID = download.item.seriesID ?? download.item.parentBackdropItemID
                if let showID {
                    candidateShowIDs.insert(showID)
                }
            }
        }

        var results: [String] = []
        for showID in candidateShowIDs {
            if isShowFullyDownloaded(showID, downloadManager: downloadManager) {
                results.append(showID)
            }
        }
        return results.sorted { (library.item(for: $0)?.name ?? "") < (library.item(for: $1)?.name ?? "") }
    }

    /// Only returns downloaded episodes if their whole show isn't downloaded.
    func downloadedEpisodeIDs(downloadManager: DownloadManager) -> [String] {
        downloadManager.completedDownloads
            .map(\.item)
            .filter { item in
                guard item.type == .episode || item.seriesName != nil else { return false }
                guard let showID = item.seriesID ?? item.parentBackdropItemID else { return true }
                return !isShowFullyDownloaded(showID, downloadManager: downloadManager)
            }
            .compactMap(\.id)
    }

    /// Returns downloaded movie IDs.
    func downloadedMovieIDs(downloadManager: DownloadManager) -> [String] {
        downloadManager.downloadedMovies.compactMap(\.id)
    }

    // MARK: - Sections

    /// Favorited collections, shows, episodes, and movies. Empty sections are dropped.
    var favoriteSections: [MediaSection] {
        [
            MediaSection(title: "Collections", itemIDs: favoriteCollectionIDs),
            MediaSection(title: "TV Shows", itemIDs: favoriteShowIDs),
            MediaSection(title: "Episodes", itemIDs: favoriteEpisodeIDs),
            MediaSection(title: "Movies", itemIDs: favoriteMovieIDs),
        ]
        .filter { !$0.itemIDs.isEmpty }
    }

    /// Fully downloaded shows plus any individually downloaded episodes and movies.
    func downloadSections(downloadManager: DownloadManager) -> [MediaSection] {
        [
            MediaSection(title: "TV Shows", itemIDs: downloadedShowIDs(downloadManager: downloadManager)),
            MediaSection(title: "Episodes", itemIDs: downloadedEpisodeIDs(downloadManager: downloadManager)),
            MediaSection(title: "Movies", itemIDs: downloadedMovieIDs(downloadManager: downloadManager)),
        ]
        .filter { !$0.itemIDs.isEmpty }
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
            return regularMovieIDs.count
        case .tvShows:
            return regularShowIDs.count
        case .favorites:
            return favoriteSections.reduce(0) { $0 + $1.itemIDs.count }
        case .downloads:
            return downloadSections(downloadManager: downloadManager).reduce(0) { $0 + $1.itemIDs.count }
        }
    }

    var isLoading: Bool { library.isLoading }
    var errorMessage: String? { library.errorMessage }

    func refresh(using client: JellyfinClient) async {
        await library.refresh(using: client)
    }
}
