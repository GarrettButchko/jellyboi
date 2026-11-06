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

@Observable
@MainActor
class HomeViewModel {
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
    var tvShows: [BaseItemDto] {
        #if DEBUG
        if DebugSettings.shared.hideAllHomeRows { return [] }
        #endif
        return library.tvShows
    }
    var episodes: [BaseItemDto] {
        #if DEBUG
        if DebugSettings.shared.hideAllHomeRows { return [] }
        #endif
        return library.episodes
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
    var favorites: [BaseItemDto] {
        #if DEBUG
        if DebugSettings.shared.hideAllHomeRows { return [] }
        #endif
        return library.favorites
    }
    var completedMovies: [BaseItemDto] {
        #if DEBUG
        if DebugSettings.shared.hideAllHomeRows { return [] }
        #endif
        return library.completedMovies
    }
    var watchedMovies: [BaseItemDto] {
        #if DEBUG
        if DebugSettings.shared.hideAllHomeRows { return [] }
        #endif
        return library.watchedMovies
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

    // MARK: - Carousel Composition & State

    var carouselTitle: String {
        (!topWatchedMovies.isEmpty || !resumeShows.isEmpty) ? "Continue Watching" : "Featured"
    }

    /// Items shown in the hero carousel. Precomputed in background by LibraryViewModel.
    var carouselItems: [BaseItemDto] {
        #if DEBUG
        if DebugSettings.shared.hideAllHomeRows { return [] }
        #endif
        return library.carouselItems
    }

    /// Preserved carousel looped index so that navigating to another view and back
    /// does not reset the carousel back to slide 0.
    @ObservationIgnored
    var carouselSnappedIndex: Int? = nil

    /// The item currently selected/focused in the hero carousel based on carouselSnappedIndex.
    var currentCarouselItem: BaseItemDto? {
        guard !carouselItems.isEmpty else { return nil }
        if let snapped = carouselSnappedIndex {
            let count = carouselItems.count
            guard count > 0 else { return carouselItems.first }
            let idx = ((snapped % count) + count) % count
            if carouselItems.indices.contains(idx) {
                return carouselItems[idx]
            }
        }
        return carouselItems.first
    }

    func load(using client: JellyfinClient) async {
        await library.load(using: client)
    }

    func refresh(using client: JellyfinClient) async {
        await library.refresh(using: client)
    }
}
