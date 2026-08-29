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

    var title: String {
        switch self {
        case .movies: "Movies"
        case .tvShows: "TV Shows"
        }
    }

    var itemType: BaseItemKind {
        switch self {
        case .movies: .movie
        case .tvShows: .series
        }
    }
}

@Observable
@MainActor
class MediaViewModel {
    var filter: MediaFilter = .movies
    var library = LibraryViewModel()

    init(library: LibraryViewModel? = nil) {
        if let library { self.library = library }
    }

    var currentItems: [BaseItemDto] {
        filter == .movies ? library.movies : library.tvShows
    }

    var isLoading: Bool { library.isLoading }
    var errorMessage: String? { library.errorMessage }

    func refresh(using client: JellyfinClient) async {
        await library.refresh(using: client)
    }
}
