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

enum SearchSort: CaseIterable, Hashable {
    case nameAsc, recentlyAdded, rating

    var title: String {
        switch self {
        case .nameAsc:       "A–Z"
        case .recentlyAdded: "Recently Added"
        case .rating:        "Top Rated"
        }
    }
}

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
    var sort: SearchSort = .nameAsc
    var showFavoritesOnly: Bool = false

    init(library: LibraryViewModel? = nil) {
        if let library { self.library = library }
    }

    // MARK: Derived state

    /// All movies+shows available to search/filter, narrowed to favorites when toggled.
    private var pool: [BaseItemDto] {
        let all = library.movies + library.tvShows
        return showFavoritesOnly ? all.filter { $0.userData?.isFavorite == true } : all
    }

    /// Items matching the current search text, sorted by `sort`.
    /// Returns an empty array when `searchText` is empty (genre grid shown instead).
    var results: [BaseItemDto] {
        guard !searchText.isEmpty else { return [] }
        let query = searchText.lowercased()
        let filtered = pool.filter { ($0.name ?? "").lowercased().contains(query) }
        return sorted(filtered)
    }

    /// Unique genres derived from the current scope (All / Movies / Shows), sorted by
    /// frequency descending then alphabetically.
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

    /// All items (from the scoped pool) that belong to a given genre, sorted by `sort`.
    func items(inGenre name: String) -> [BaseItemDto] {
        let matching = pool.filter { $0.genres?.contains(name) == true }
        return sorted(matching)
    }

    // MARK: State proxies

    var isLoading: Bool   { library.isLoading }
    var errorMessage: String? { library.errorMessage }

    // MARK: Helpers

    private func sorted(_ items: [BaseItemDto]) -> [BaseItemDto] {
        switch sort {
        case .nameAsc:
            return items.sorted { ($0.sortName ?? $0.name ?? "") < ($1.sortName ?? $1.name ?? "") }
        case .recentlyAdded:
            return items.sorted { ($0.dateCreated ?? .distantPast) > ($1.dateCreated ?? .distantPast) }
        case .rating:
            return items.sorted { ($0.communityRating ?? 0) > ($1.communityRating ?? 0) }
        }
    }
}
