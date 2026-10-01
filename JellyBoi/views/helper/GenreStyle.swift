//
//  GenreStyle.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 8/28/26.
//

import SwiftUI

/// Visual style (icon + accent color) for a genre chip.
struct GenreStyle {
    let icon: String
    let color: Color

    // MARK: - Lookup

    static func forGenre(_ name: String) -> GenreStyle {
        let key = name.lowercased().trimmingCharacters(in: .whitespaces)
        return knownGenres[key] ?? fallback(for: name)
    }

    // MARK: - Known genres

    private static let knownGenres: [String: GenreStyle] = [
        "action":          GenreStyle(icon: "bolt.fill",                              color: .red),
        "adventure":       GenreStyle(icon: "map.fill",                               color: .orange),
        "animation":       GenreStyle(icon: "sparkles",                               color: .mint),
        "anime":           GenreStyle(icon: "star.fill",                              color: .pink),
        "biography":       GenreStyle(icon: "person.text.rectangle.fill",             color: .purple),
        "comedy":          GenreStyle(icon: "theatermasks.fill",                      color: .yellow),
        "crime":           GenreStyle(icon: "magnifyingglass",                        color: .blue),
        "documentary":     GenreStyle(icon: "book.fill",                              color: .teal),
        "drama":           GenreStyle(icon: "quote.bubble.fill",                      color: .indigo),
        "family":          GenreStyle(icon: "figure.2.and.child.holdinghands",        color: .green),
        "fantasy":         GenreStyle(icon: "wand.and.stars",                         color: .purple),
        "history":         GenreStyle(icon: "building.columns.fill",                  color: .orange),
        "horror":          GenreStyle(icon: "moon.fill",                              color: .indigo),
        "kids":            GenreStyle(icon: "figure.child.circle.fill",               color: .cyan),
        "music":           GenreStyle(icon: "music.note",                             color: .pink),
        "musical":         GenreStyle(icon: "music.mic",                              color: .pink),
        "mystery":         GenreStyle(icon: "questionmark.circle.fill",               color: .blue),
        "news":            GenreStyle(icon: "newspaper.fill",                         color: .cyan),
        "reality":         GenreStyle(icon: "camera.fill",                            color: .teal),
        "romance":         GenreStyle(icon: "heart.fill",                             color: .pink),
        "science fiction": GenreStyle(icon: "antenna.radiowaves.left.and.right",      color: .teal),
        "sci-fi":          GenreStyle(icon: "antenna.radiowaves.left.and.right",      color: .teal),
        "sci-fi & fantasy":GenreStyle(icon: "sparkle",                               color: .indigo),
        "short":           GenreStyle(icon: "timer",                                  color: .mint),
        "sport":           GenreStyle(icon: "figure.run",                             color: .green),
        "sports":          GenreStyle(icon: "figure.run",                             color: .green),
        "talk":            GenreStyle(icon: "mic.fill",                               color: .cyan),
        "thriller":        GenreStyle(icon: "eye.fill",                               color: .red),
        "war":             GenreStyle(icon: "shield.fill",                            color: .orange),
        "western":         GenreStyle(icon: "sun.max.fill",                           color: .yellow),
    ]

    // MARK: - Deterministic fallback

    /// Fallback palette for genres not in the known map.
    /// Uses a stable hash of the name so the same genre always gets the same color.
    private static let fallbackIcons  = ["film.fill", "tv.fill", "play.rectangle.fill", "square.grid.2x2.fill"]
    private static let fallbackColors: [Color] = [
        .red,
        .orange,
        .yellow,
        .green,
        .mint,
        .teal,
        .cyan,
        .blue,
        .indigo,
        .purple,
        .pink
    ]

    private static func fallback(for name: String) -> GenreStyle {
        let hash = abs(name.unicodeScalars.reduce(0) { ($0 &* 31) &+ Int(bitPattern: UInt(UInt32($1.value))) })
        let icon  = fallbackIcons[hash  % fallbackIcons.count]
        let color = fallbackColors[hash % fallbackColors.count]
        return GenreStyle(icon: icon, color: color)
    }
}
