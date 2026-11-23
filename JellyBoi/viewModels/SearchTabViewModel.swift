//
//  SearchTabViewModel.swift
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
final class SearchTabViewModel {

    static let shared = SearchTabViewModel()

    private let library: LibraryViewModel
    var searchText = ""

    private let ranker = MediaSearchRanker()

    init(library: LibraryViewModel? = nil) {
        self.library = library ?? .shared
    }

    // MARK: Derived state

    private var poolIDs: [String] {
        library.movieIDs + library.tvShowIDs
    }

    private var searchPool: [BaseItemDto] {
        (library.movieIDs + library.tvShowIDs + library.episodeIDs + library.collectionIDs)
            .compactMap { library.item(for: $0) }
    }

    /// Item IDs matching the current search text, ordered by relevance score descending.
    var resultIDs: [String] {
        #if DEBUG
        if DebugSettings.shared.simulateSearchEmptyLibrary || DebugSettings.shared.hideSearchResults { return [] }
        #endif
        return ranker.results(for: searchText, in: searchPool).compactMap(\.id)
    }

    /// Unique genres derived from movies + shows, sorted by frequency descending then alphabetically.
    var genres: [GenreCount] {
        #if DEBUG
        if DebugSettings.shared.simulateSearchEmptyLibrary || DebugSettings.shared.hideSearchGenres { return [] }
        #endif
        return library.genres
    }

    /// All item IDs (from the movies+shows pool) that belong to a given genre, sorted A–Z.
    func itemIDs(inGenre name: String) -> [String] {
        #if DEBUG
        if DebugSettings.shared.simulateSearchEmptyLibrary || DebugSettings.shared.hideGenreResults { return [] }
        #endif
        return poolIDs
            .filter { library.item(for: $0)?.genres?.contains(name) == true }
            .sorted { lhs, rhs in
                let a = library.item(for: lhs)?.sortName ?? library.item(for: lhs)?.name ?? ""
                let b = library.item(for: rhs)?.sortName ?? library.item(for: rhs)?.name ?? ""
                return a < b
            }
    }

    // MARK: State proxies

    var isLoading: Bool   { library.isLoading }
    var errorMessage: String? { library.errorMessage }
}
