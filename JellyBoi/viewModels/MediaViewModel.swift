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
    case collections

    var title: String {
        switch self {
        case .movies: "Movies"
        case .tvShows: "TV Shows"
        case .collections: "Collections"
        }
    }

    var itemType: BaseItemKind {
        switch self {
        case .movies: .movie
        case .tvShows: .series
        case .collections: .boxSet
        }
    }
}

@Observable
@MainActor
class MediaViewModel {
    private var _filter: MediaFilter = .movies
    var filter: MediaFilter {
        get {
            if _filter == .collections && !hasCollections {
                return .movies
            }
            return _filter
        }
        set {
            _filter = newValue
        }
    }
    var showFavoritesOnly: Bool = false
    var library = LibraryViewModel()

    var hasCollections: Bool {
        #if DEBUG
        if DebugSettings.shared.simulateMediaEmptyLibrary || DebugSettings.shared.hideMediaCollections { return false }
        #endif
        return !library.collections.isEmpty
    }

    var availableFilters: [MediaFilter] {
        var filters: [MediaFilter] = [.movies, .tvShows]
        if hasCollections {
            filters.append(.collections)
        }
        return filters
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
        case .collections:
            if DebugSettings.shared.hideMediaCollections { return [] }
        }
        #endif
        switch filter {
        case .movies: return library.movies
        case .tvShows: return library.tvShows
        case .collections: return library.collections
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

    var favoriteEpisodes: [BaseItemDto] {
        #if DEBUG
        if DebugSettings.shared.simulateMediaEmptyLibrary || DebugSettings.shared.hideMediaFavorites { return [] }
        #endif
        return library.episodes.filter { $0.userData?.isFavorite == true }
    }

    var favoriteCollections: [BaseItemDto] {
        #if DEBUG
        if DebugSettings.shared.simulateMediaEmptyLibrary || DebugSettings.shared.hideMediaFavorites { return [] }
        #endif
        return library.collections.filter { $0.userData?.isFavorite == true }
    }

    var favoriteTvItems: [BaseItemDto] {
        favoriteShows + favoriteEpisodes
    }

    var currentFavoriteItems: [BaseItemDto] {
        switch filter {
        case .movies: favoriteMovies
        case .tvShows: favoriteTvItems
        case .collections: favoriteCollections
        }
    }

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
