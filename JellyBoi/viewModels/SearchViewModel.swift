//
//  SearchViewModel.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 8/28/26.
//

import Foundation
import Observation
import JellyfinAPI

// MARK: - Supporting types

struct GenreCount: Identifiable, Hashable {
    let name: String
    let count: Int
    var id: String { name }
}

// MARK: - ViewModel

@Observable
@MainActor
class SearchViewModel {
    var library = LibraryViewModel()
    var searchText = ""
    var showFavoritesOnly: Bool = false

    private let ranker = MediaSearchRanker()

    init(library: LibraryViewModel? = nil) {
        if let library { self.library = library }
    }

    // MARK: Derived state

    /// Movies + shows only, narrowed to favorites when toggled.
    /// Used for genre browse, `items(inGenre:)`, and `previewItem(forGenre:)`.
    private var pool: [BaseItemDto] {
        let all = library.movies + library.tvShows
        return showFavoritesOnly ? all.filter { $0.userData?.isFavorite == true } : all
    }

    /// Full pool including episodes, used when the user is actively searching.
    private var searchPool: [BaseItemDto] {
        let all = library.movies + library.tvShows + library.episodes
        return showFavoritesOnly ? all.filter { $0.userData?.isFavorite == true } : all
    }

    /// Items matching the current search text, ordered by relevance score descending.
    /// Returns an empty array when `searchText` is empty (genre grid shown instead).
    var results: [BaseItemDto] {
        ranker.results(for: searchText, in: searchPool)
    }

    /// Unique genres derived from movies + shows, sorted by frequency descending then alphabetically.
    var genres: [GenreCount] {
        var counts: [String: Int] = [:]
        for item in pool {
            for genre in item.genres ?? [] {
                counts[genre, default: 0] += 1
            }
        }
        return counts
            .map { GenreCount(name: $0.key, count: $0.value) }
            .sorted { lhs, rhs in
                lhs.count != rhs.count ? lhs.count > rhs.count : lhs.name < rhs.name
            }
    }

    /// All items (from the movies+shows pool) that belong to a given genre, sorted A–Z.
    func items(inGenre name: String) -> [BaseItemDto] {
        pool
            .filter { $0.genres?.contains(name) == true }
            .sorted { ($0.sortName ?? $0.name ?? "") < ($1.sortName ?? $1.name ?? "") }
    }

    /// A representative item for a genre, used as a background image on genre cards.
    func previewItem(forGenre name: String) -> BaseItemDto? {
        pool.first { $0.genres?.contains(name) == true }
    }

    // MARK: State proxies

    var isLoading: Bool   { library.isLoading }
    var errorMessage: String? { library.errorMessage }
}
