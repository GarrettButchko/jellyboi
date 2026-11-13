//
//  MediaAspectRatio.swift
//  JellyBoi
//

import CoreGraphics

/// Canonical width / height ratios for the artwork shapes used throughout the app.
///
/// Cards, grids, the hero, and the carousel all render the same poster and thumbnail shapes, so the
/// values live here once. Call these instead of writing `2.0 / 3.0` or `16.0 / 9.0` at each call
/// site, otherwise a single row can silently drift out of shape.
nonisolated enum MediaAspectRatio {

    /// Portrait poster ratio (2:3) used by movie, series, and person cards.
    static let poster: CGFloat = 2.0 / 3.0

    /// Landscape still ratio (16:9) used by episode, video, special feature, and hero artwork.
    static let thumbnail: CGFloat = 16.0 / 9.0
}
