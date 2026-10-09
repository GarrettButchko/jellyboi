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

@Observable
@MainActor
class MediaViewModel {
    var filter: MediaFilter = .movies
    var showFavoritesOnly: Bool = false
    var showDownloadsOnly: Bool = false
    var library = LibraryViewModel()

    var availableFilters: [MediaFilter] {
        MediaFilter.allCases
    }

    init(library: LibraryViewModel? = nil) {
        if let library { self.library = library }
    }

    // MARK: - Regular Browsing Items

    var regularItems: [BaseItemDto] {
        #if DEBUG
        if DebugSettings.shared.simulateMediaEmptyLibrary { return [] }
        switch filter {
        case .movies:
            if DebugSettings.shared.hideMediaMovies { return [] }
        case .tvShows:
            if DebugSettings.shared.hideMediaShows { return [] }
        }
        #endif
        switch filter {
        case .movies: return library.movies
        case .tvShows: return library.tvShows
        }
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

    var favoriteTvItems: [BaseItemDto] {
        favoriteShows + favoriteEpisodes
    }

    var currentFavoriteItems: [BaseItemDto] {
        switch filter {
        case .movies: favoriteMovies
        case .tvShows: favoriteTvItems
        }
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
    func downloadedEpisodes(downloadManager: DownloadManager) -> [BaseItemDto] {
        downloadManager.completedDownloads
            .map(\.item)
            .filter { item in
                guard item.type == .episode || item.seriesName != nil else { return false }
                guard let showID = item.seriesID ?? item.parentBackdropItemID else { return true }
                return !isShowFullyDownloaded(showID, downloadManager: downloadManager)
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
}
