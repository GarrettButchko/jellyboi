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
    var filter: MediaFilter = .movies
    var showFavoritesOnly: Bool = false
    var library = LibraryViewModel()

    init(library: LibraryViewModel? = nil) {
        if let library { self.library = library }
    }

    // MARK: - Regular Browsing Items

    var regularItems: [BaseItemDto] {
        switch filter {
        case .movies: library.movies
        case .tvShows: library.tvShows
        case .collections: library.collections
        }
    }

    // MARK: - Favorite Items

    var favoriteMovies: [BaseItemDto] {
        library.movies.filter { $0.userData?.isFavorite == true }
    }

    var favoriteShows: [BaseItemDto] {
        library.tvShows.filter { $0.userData?.isFavorite == true }
    }

    var favoriteEpisodes: [BaseItemDto] {
        library.episodes.filter { $0.userData?.isFavorite == true }
    }

    var favoriteCollections: [BaseItemDto] {
        library.collections.filter { $0.userData?.isFavorite == true }
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
    var errorMessage: String? { library.errorMessage }

    func refresh(using client: JellyfinClient) async {
        await library.refresh(using: client)
    }
}
