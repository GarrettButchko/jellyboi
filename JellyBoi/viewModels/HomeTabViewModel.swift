//
//  HomeTabViewModel.swift
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
final class HomeTabViewModel {

    static let shared = HomeTabViewModel()

    private let library: LibraryViewModel

    init(library: LibraryViewModel? = nil) {
        self.library = library ?? .shared
    }

    var movieIDs: [String] {
        #if DEBUG
        if DebugSettings.shared.hideAllHomeRows { return [] }
        #endif
        return library.movieIDs
    }
    var tvShowIDs: [String] {
        #if DEBUG
        if DebugSettings.shared.hideAllHomeRows { return [] }
        #endif
        return library.tvShowIDs
    }
    var episodeIDs: [String] {
        #if DEBUG
        if DebugSettings.shared.hideAllHomeRows { return [] }
        #endif
        return library.episodeIDs
    }
    var collectionIDs: [String] {
        #if DEBUG
        if DebugSettings.shared.hideAllHomeRows || DebugSettings.shared.hideCollections { return [] }
        #endif
        return library.collectionIDs
    }
    var recommendedIDs: [String] {
        #if DEBUG
        if DebugSettings.shared.hideAllHomeRows || DebugSettings.shared.hideTopRated { return [] }
        #endif
        return library.recommendedIDs
    }
    var recentlyAddedMovieIDs: [String] {
        #if DEBUG
        if DebugSettings.shared.hideAllHomeRows || DebugSettings.shared.hideRecentlyAddedMovies { return [] }
        #endif
        return library.recentlyAddedMovieIDs
    }
    var recentlyAddedShowIDs: [String] {
        #if DEBUG
        if DebugSettings.shared.hideAllHomeRows || DebugSettings.shared.hideRecentlyAddedShows { return [] }
        #endif
        return library.recentlyAddedShowIDs
    }
    var inProgressMovieIDs: [String] {
        #if DEBUG
        if DebugSettings.shared.hideAllHomeRows || DebugSettings.shared.hideContinueWatching { return [] }
        #endif
        return library.inProgressMovieIDs
    }
    var topWatchedMovieIDs: [String] {
        #if DEBUG
        if DebugSettings.shared.hideAllHomeRows || DebugSettings.shared.hideContinueWatching { return [] }
        #endif
        return library.topWatchedMovieIDs
    }
    var resumeShowIDs: [String] {
        #if DEBUG
        if DebugSettings.shared.hideAllHomeRows || DebugSettings.shared.hideContinueShows { return [] }
        #endif
        return library.resumeShowIDs
    }
    var favoriteIDs: [String] {
        #if DEBUG
        if DebugSettings.shared.hideAllHomeRows { return [] }
        #endif
        return library.favoriteIDs
    }
    var completedMovieIDs: [String] {
        #if DEBUG
        if DebugSettings.shared.hideAllHomeRows { return [] }
        #endif
        return library.completedMovieIDs
    }
    var watchedMovieIDs: [String] {
        #if DEBUG
        if DebugSettings.shared.hideAllHomeRows { return [] }
        #endif
        return library.watchedMovieIDs
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
        (!topWatchedMovieIDs.isEmpty || !resumeShowIDs.isEmpty) ? "Continue Watching" : "Featured"
    }

    /// Item IDs shown in the hero carousel. Precomputed in background by LibraryViewModel.
    var carouselItemIDs: [String] {
        #if DEBUG
        if DebugSettings.shared.hideAllHomeRows || DebugSettings.shared.hideCarousel { return [] }
        #endif
        return library.carouselItemIDs
    }

    /// Preserved carousel looped index so that navigating to another view and back
    /// does not reset the carousel back to slide 0.
    @ObservationIgnored
    var carouselSnappedIndex: Int? = nil

    /// The item currently selected/focused in the hero carousel based on carouselSnappedIndex.
    var currentCarouselItemID: String? {
        guard !carouselItemIDs.isEmpty else { return nil }
        if let snapped = carouselSnappedIndex {
            let count = carouselItemIDs.count
            guard count > 0 else { return carouselItemIDs.first }
            let idx = ((snapped % count) + count) % count
            if carouselItemIDs.indices.contains(idx) {
                return carouselItemIDs[idx]
            }
        }
        return carouselItemIDs.first
    }

    func item(for id: String) -> BaseItemDto? {
        library.item(for: id)
    }

    func load(using client: JellyfinClient? = nil) async {
        guard let client = client ?? ServerViewModel.shared.client else { return }
        await library.load(using: client)
    }

    func refresh(using client: JellyfinClient? = nil) async {
        guard let client = client ?? ServerViewModel.shared.client else { return }
        await library.refresh(using: client)
    }
}
