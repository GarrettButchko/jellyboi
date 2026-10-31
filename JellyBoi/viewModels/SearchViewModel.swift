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

public struct GenreCount: Identifiable, Hashable, Sendable {
    public let name: String
    public let count: Int
    public var id: String { name }

    public init(name: String, count: Int) {
        self.name = name
        self.count = count
    }
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

    /// Full pool including episodes and collections, used when the user is actively searching.
    private var searchPool: [BaseItemDto] {
        let all = library.movies + library.tvShows + library.episodes + library.collections
        return showFavoritesOnly ? all.filter { $0.userData?.isFavorite == true } : all
    }

    /// Items matching the current search text, ordered by relevance score descending.
    /// Returns an empty array when `searchText` is empty (genre grid shown instead).
    var results: [BaseItemDto] {
        #if DEBUG
        if DebugSettings.shared.simulateSearchEmptyLibrary || DebugSettings.shared.hideSearchResults { return [] }
        #endif
        return ranker.results(for: searchText, in: searchPool)
    }

    /// Unique genres derived from movies + shows, sorted by frequency descending then alphabetically.
    var genres: [GenreCount] {
        #if DEBUG
        if DebugSettings.shared.simulateSearchEmptyLibrary || DebugSettings.shared.hideSearchGenres { return [] }
        #endif
        if !showFavoritesOnly && !library.genres.isEmpty {
            return library.genres
        }
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
        #if DEBUG
        if DebugSettings.shared.simulateSearchEmptyLibrary || DebugSettings.shared.hideGenreResults { return [] }
        #endif
        return pool
            .filter { $0.genres?.contains(name) == true }
            .sorted { ($0.sortName ?? $0.name ?? "") < ($1.sortName ?? $1.name ?? "") }
    }

    /// A mapping of genre names to representative media items for genre card background images.
    /// Uses maximum bipartite matching to ensure each genre gets a distinct movie/show image.
    /// If a genre only has one item or all its candidates are exhausted, it safely falls back
    /// to an available item even if shared.
    var previewItems: [String: BaseItemDto] {
        var genreCandidates: [String: [BaseItemDto]] = [:]
        var itemByID: [String: BaseItemDto] = [:]

        for item in pool {
            if let id = item.id {
                itemByID[id] = item
            }
            for genre in item.genres ?? [] {
                genreCandidates[genre, default: []].append(item)
            }
        }

        // Prefer items with backdrop images first, keeping deterministic alphabetical sort
        for (genre, items) in genreCandidates {
            genreCandidates[genre] = items.sorted { item1, item2 in
                let b1 = !(item1.backdropImageTags ?? []).isEmpty
                let b2 = !(item2.backdropImageTags ?? []).isEmpty
                if b1 != b2 { return b1 && !b2 }
                return (item1.sortName ?? item1.name ?? "") < (item2.sortName ?? item2.name ?? "")
            }
        }

        let allGenres = genres.map(\.name)

        // Sort genres with fewer candidates first to prioritize constrained genres
        let sortedGenres = allGenres.sorted {
            let count1 = genreCandidates[$0]?.count ?? 0
            let count2 = genreCandidates[$1]?.count ?? 0
            if count1 != count2 { return count1 < count2 }
            return $0 < $1
        }

        // Maximum bipartite matching via augmenting paths (Kuhn's algorithm)
        var match: [String: String] = [:] // itemID -> genre

        func bpm(genre: String, visited: inout Set<String>) -> Bool {
            guard let candidates = genreCandidates[genre] else { return false }
            for item in candidates {
                guard let itemID = item.id else { continue }
                if visited.contains(itemID) { continue }
                visited.insert(itemID)

                if let currentGenre = match[itemID] {
                    if bpm(genre: currentGenre, visited: &visited) {
                        match[itemID] = genre
                        return true
                    }
                } else {
                    match[itemID] = genre
                    return true
                }
            }
            return false
        }

        for genre in sortedGenres {
            var visited = Set<String>()
            _ = bpm(genre: genre, visited: &visited)
        }

        var result: [String: BaseItemDto] = [:]
        for (itemID, genre) in match {
            if let item = itemByID[itemID] {
                result[genre] = item
            }
        }

        // Fallback for any genre that couldn't be matched uniquely (e.g. only 1 item available or all shared)
        for genre in allGenres {
            if result[genre] == nil {
                result[genre] = genreCandidates[genre]?.first
            }
        }

        return result
    }

    /// A representative item for a genre, used as a background image on genre cards.
    func previewItem(forGenre name: String) -> BaseItemDto? {
        previewItems[name]
    }

    // MARK: State proxies

    var isLoading: Bool   { library.isLoading }
    var errorMessage: String? { library.errorMessage }
}
