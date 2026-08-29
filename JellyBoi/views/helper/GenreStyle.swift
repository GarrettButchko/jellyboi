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
        "biography":       GenreStyle(icon: "person.text.rectangle.fill",             color: .brown),
        "comedy":          GenreStyle(icon: "theatermasks.fill",                      color: .yellow),
        "crime":           GenreStyle(icon: "magnifyingglass",                        color: Color(red: 0.4, green: 0.4, blue: 0.45)),
        "documentary":     GenreStyle(icon: "book.fill",                              color: .brown),
        "drama":           GenreStyle(icon: "quote.bubble.fill",                      color: .purple),
        "family":          GenreStyle(icon: "figure.2.and.child.holdinghands",        color: .green),
        "fantasy":         GenreStyle(icon: "wand.and.stars",                         color: Color(red: 0.55, green: 0.3, blue: 0.8)),
        "history":         GenreStyle(icon: "building.columns.fill",                  color: .brown),
        "horror":          GenreStyle(icon: "moon.fill",                              color: .indigo),
        "kids":            GenreStyle(icon: "figure.child.circle.fill",               color: .teal),
        "music":           GenreStyle(icon: "music.note",                             color: Color(red: 0.9, green: 0.35, blue: 0.5)),
        "musical":         GenreStyle(icon: "music.mic",                              color: Color(red: 0.9, green: 0.4, blue: 0.55)),
        "mystery":         GenreStyle(icon: "questionmark.circle.fill",               color: Color(red: 0.3, green: 0.4, blue: 0.6)),
        "news":            GenreStyle(icon: "newspaper.fill",                         color: .gray),
        "reality":         GenreStyle(icon: "camera.fill",                            color: .cyan),
        "romance":         GenreStyle(icon: "heart.fill",                             color: Color(red: 0.95, green: 0.3, blue: 0.5)),
        "science fiction": GenreStyle(icon: "antenna.radiowaves.left.and.right",      color: .teal),
        "sci-fi":          GenreStyle(icon: "antenna.radiowaves.left.and.right",      color: .teal),
        "sci-fi & fantasy":GenreStyle(icon: "sparkle",                               color: .teal),
        "short":           GenreStyle(icon: "timer",                                  color: .gray),
        "sport":           GenreStyle(icon: "figure.run",                             color: .green),
        "sports":          GenreStyle(icon: "figure.run",                             color: .green),
        "talk":            GenreStyle(icon: "mic.fill",                               color: .cyan),
        "thriller":        GenreStyle(icon: "eye.fill",                               color: Color(red: 0.45, green: 0.45, blue: 0.5)),
        "war":             GenreStyle(icon: "shield.fill",                            color: Color(red: 0.5, green: 0.4, blue: 0.3)),
        "western":         GenreStyle(icon: "sun.max.fill",                           color: .orange),
    ]

    // MARK: - Deterministic fallback

    /// Fallback palette for genres not in the known map.
    /// Uses a stable hash of the name so the same genre always gets the same color.
    private static let fallbackIcons  = ["film.fill", "tv.fill", "play.rectangle.fill", "square.grid.2x2.fill"]
    private static let fallbackColors: [Color] = [
        Color(red: 0.6, green: 0.3, blue: 0.7),
        Color(red: 0.2, green: 0.6, blue: 0.6),
        Color(red: 0.7, green: 0.4, blue: 0.2),
        Color(red: 0.3, green: 0.5, blue: 0.7),
        Color(red: 0.7, green: 0.3, blue: 0.4),
        Color(red: 0.4, green: 0.65, blue: 0.3),
    ]

    private static func fallback(for name: String) -> GenreStyle {
        let hash = abs(name.unicodeScalars.reduce(0) { ($0 &* 31) &+ Int(bitPattern: UInt(UInt32($1.value))) })
        let icon  = fallbackIcons[hash  % fallbackIcons.count]
        let color = fallbackColors[hash % fallbackColors.count]
        return GenreStyle(icon: icon, color: color)
    }
}
