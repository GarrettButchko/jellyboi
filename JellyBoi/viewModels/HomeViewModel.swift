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

    var movies: [BaseItemDto] { library.movies }
    var collections: [BaseItemDto] { library.collections }
    var recommended: [BaseItemDto] { library.recommended }
    var recentlyAdded: [BaseItemDto] { library.recentlyAdded }
    var inProgressMovies: [BaseItemDto] { library.inProgressMovies }
    var topWatchedMovies: [BaseItemDto] { library.topWatchedMovies }
    var resumeShows: [BaseItemDto] { library.resumeShows }
    var tvSeriesCount: Int { library.tvSeriesCount }
    var episodeCount: Int { library.episodeCount }
    var favoritesCount: Int { library.favoritesCount }
    var completedCount: Int { library.completedCount }
    var watchedHours: Int { library.watchedHours }

    var isLoading: Bool { library.isLoading }
    var errorMessage: String? { library.errorMessage }
    var isLibraryEmpty: Bool { library.isLibraryEmpty }

    /// Items shown in the hero carousel. Falls back to Recently Added when the user
    /// has no in-progress movies, so the carousel is never blank.
    var carouselItems: [BaseItemDto] { topWatchedMovies.isEmpty ? recentlyAdded : topWatchedMovies }

    func load(using client: JellyfinClient) async {
        await library.load(using: client)
    }

    func refresh(using client: JellyfinClient) async {
        await library.refresh(using: client)
    }
}
