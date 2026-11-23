//
//  ItemType.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 11/20/26.
//

import Foundation
import JellyfinAPI

/// Represents the kind of media item displayed in `MediaDetailView`.
enum ItemType: Equatable, Hashable, Sendable {
    /// An episode navigated to from the show detail view.
    case episodeWithShow
    /// An episode navigated to independently (needs a button to navigate to its show).
    case episodeWithoutShow
    /// A movie.
    case movie
    /// A television series / show.
    case series
    /// A box set / collection.
    case collection
    /// A playlist.
    case playlist
    
    case none
    
    /// Whether this item represents an episode.
    var isEpisode: Bool {
        self == .episodeWithShow || self == .episodeWithoutShow
    }

    /// Derives the default `ItemType` from Jellyfin's `BaseItemKind`.
    static func from(dtoKind: BaseItemKind?) -> ItemType {
        switch dtoKind {
        case .episode:
            return .episodeWithShow
        case .series:
            return .series
        case .boxSet:
            return .collection
        case .playlist:
            return .playlist
        case .movie:
            return .movie
        default:
            return .movie
        }
    }
}
