//
//  HomeViewModel.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 8/24/26.
//

import Foundation
import Observation
import Get
import JellyfinAPI
internal import Combine

@Observable
@MainActor
class HomeViewModel: ObservableObject {
    var library = LibraryViewModel()

    init(library: LibraryViewModel? = nil) {
        if let library { self.library = library }
    }

    var movies: [BaseItemDto] {
        #if DEBUG
        if DebugSettings.shared.hideAllHomeRows { return [] }
        #endif
        return library.movies
    }
    var collections: [BaseItemDto] {
        #if DEBUG
        if DebugSettings.shared.hideAllHomeRows || DebugSettings.shared.hideCollections { return [] }
        #endif
        return library.collections
    }
    var recommended: [BaseItemDto] {
        #if DEBUG
        if DebugSettings.shared.hideAllHomeRows || DebugSettings.shared.hideTopRated { return [] }
        #endif
        return library.recommended
    }
    var recentlyAddedMovies: [BaseItemDto] {
        #if DEBUG
        if DebugSettings.shared.hideAllHomeRows || DebugSettings.shared.hideRecentlyAddedMovies { return [] }
        #endif
        return library.recentlyAddedMovies
    }
    var recentlyAddedShows: [BaseItemDto] {
        #if DEBUG
        if DebugSettings.shared.hideAllHomeRows || DebugSettings.shared.hideRecentlyAddedShows { return [] }
        #endif
        return library.recentlyAddedShows
    }
    var recentlyAdded: [BaseItemDto] {
        #if DEBUG
        if DebugSettings.shared.hideAllHomeRows { return [] }
        #endif
        return library.recentlyAdded
    }
    var inProgressMovies: [BaseItemDto] {
        #if DEBUG
        if DebugSettings.shared.hideAllHomeRows || DebugSettings.shared.hideContinueWatching { return [] }
        #endif
        return library.inProgressMovies
    }
    var topWatchedMovies: [BaseItemDto] {
        #if DEBUG
        if DebugSettings.shared.hideAllHomeRows || DebugSettings.shared.hideContinueWatching { return [] }
        #endif
        return library.topWatchedMovies
    }
    var resumeShows: [BaseItemDto] {
        #if DEBUG
        if DebugSettings.shared.hideAllHomeRows || DebugSettings.shared.hideContinueShows { return [] }
        #endif
        return library.resumeShows
    }
    var tvSeriesCount: Int { library.tvSeriesCount }
    var episodeCount: Int { library.episodeCount }
    var favoritesCount: Int { library.favoritesCount }
    var completedCount: Int { library.completedCount }
    var watchedHours: Int { library.watchedHours }

    var isLoading: Bool { library.isLoading }
    var errorMessage: String? {
        #if DEBUG
        if DebugSettings.shared.simulateLibraryError { return "Debug: Simulated library connection error" }
        #endif
        return library.errorMessage
    }
    var isLibraryEmpty: Bool {
        #if DEBUG
        if DebugSettings.shared.simulateEmptyLibrary { return true }
        #endif
        return library.isLibraryEmpty
    }

    // MARK: - Random Featured Carousel Pool

    private var cachedRandomPoolIDs: [String] = []
    private var cachedRandomItems: [BaseItemDto] = []

    /// 6 random movies and shows from the library, reshuffled on refresh or when the library changes.
    var randomFeaturedItems: [BaseItemDto] {
        let pool = library.movies + library.tvShows
        guard !pool.isEmpty else { return [] }

        let currentPoolIDs = pool.compactMap(\.id)
        if cachedRandomPoolIDs != currentPoolIDs || cachedRandomItems.isEmpty {
            cachedRandomPoolIDs = currentPoolIDs
            cachedRandomItems = Array(pool.shuffled().prefix(6))
        }
        return cachedRandomItems
    }

    func shuffleRandomFeaturedItems() {
        let pool = library.movies + library.tvShows
        cachedRandomPoolIDs = pool.compactMap(\.id)
        cachedRandomItems = Array(pool.shuffled().prefix(6))
    }

    /// Items shown in the hero carousel.
    /// Shows `topWatchedMovies` (Continue Watching) if available;
    /// when Continue Watching disappears or is empty, falls back to 6 random movies and shows.
    var carouselItems: [BaseItemDto] {
        #if DEBUG
        if DebugSettings.shared.hideAllHomeRows { return [] }
        #endif
        if !topWatchedMovies.isEmpty {
            return Array(topWatchedMovies.prefix(6))
        }
        return randomFeaturedItems
    }

    /// Preserved carousel looped index so that navigating to another view and back
    /// does not reset the carousel back to slide 0.
    var carouselSnappedIndex: Int? = nil

    /// The item currently selected/focused in the hero carousel based on carouselSnappedIndex.
    var currentCarouselItem: BaseItemDto? {
        guard !carouselItems.isEmpty else { return nil }
        if let snapped = carouselSnappedIndex {
            let count = carouselItems.count
            let b = min(5, count)
            let idx: Int
            if snapped < b { idx = count - b + snapped }
            else if snapped >= b + count { idx = snapped - b - count }
            else { idx = snapped - b }
            if carouselItems.indices.contains(idx) {
                return carouselItems[idx]
            }
        }
        return carouselItems.first
    }

    func load(using client: JellyfinClient) async {
        await library.load(using: client)
        shuffleRandomFeaturedItems()
    }

    func refresh(using client: JellyfinClient) async {
        await library.refresh(using: client)
        shuffleRandomFeaturedItems()
    }
}
