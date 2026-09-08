//
//  MediaSearchRanker.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 9/7/26.
//

import Foundation
import JellyfinAPI

/// Scores and ranks media items against a search query across titles, genres, tags,
/// and episode metadata. The score is additive but capped per category so a single
/// very strong signal (e.g. exact title match) always beats a collection of weak ones.
///
/// Weights are intentionally easy to tune — change the `Weight` constants below.
struct MediaSearchRanker {

    // MARK: - Weights

    private enum Weight {
        // Title / series name (movies & TV shows)
        static let titleExact   = 1000
        static let titlePrefix  =  600
        static let titleContain =  400

        // Original / alternate title
        static let altTitleContain = 200

        // Genre (strongest non-title signal so genre searches surface the right shows)
        static let genreExact   = 150
        static let genreContain = 100

        // Tag
        static let tagExact   = 80
        static let tagContain = 60

        // Episode-title match (episode items only)
        static let episodeExact   = 50
        static let episodeContain = 40

        // Episode's series name (weakest — for "I remember the show name but not the episode")
        static let episodeSeriesContain = 30
    }

    // MARK: - Public API

    /// Returns the subset of `items` that match `query`, ordered by relevance score
    /// descending. Returns `[]` for an empty or whitespace-only query.
    ///
    /// - Parameters:
    ///   - query: The user-supplied search text. Trimmed and lowercased internally.
    ///   - items: The full pool to search (movies + shows + episodes, already
    ///            favorites-filtered by the caller if needed).
    func results(for query: String, in items: [BaseItemDto]) -> [BaseItemDto] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }

        return items
            .compactMap { item -> (item: BaseItemDto, score: Int)? in
                let s = score(item, query: q)
                return s > 0 ? (item, s) : nil
            }
            .sorted { $0.score > $1.score }
            .map(\.item)
    }

    // MARK: - Scoring

    private func score(_ item: BaseItemDto, query q: String) -> Int {
        if item.type == .episode {
            return scoreEpisode(item, query: q)
        } else {
            return scoreRegularItem(item, query: q)
        }
    }

    /// Score a movie or TV series: check title, original title, genres, tags.
    private func scoreRegularItem(_ item: BaseItemDto, query q: String) -> Int {
        var total = 0

        // Title — use the strongest match only (exact > prefix > contains).
        let title = (item.name ?? "").lowercased()
        if !title.isEmpty {
            if title == q {
                total += Weight.titleExact
            } else if title.hasPrefix(q) {
                total += Weight.titlePrefix
            } else if title.contains(q) {
                total += Weight.titleContain
            }
        }

        // Alternate / original title — contains only.
        let altTitle = (item.originalTitle ?? "").lowercased()
        if !altTitle.isEmpty && altTitle != title && altTitle.contains(q) {
            total += Weight.altTitleContain
        }

        // Genres — take the single best matching genre (prevents multi-genre inflation).
        if let genres = item.genres, !genres.isEmpty {
            let genreScore = genres.reduce(0) { best, genre in
                let g = genre.lowercased()
                if g == q { return max(best, Weight.genreExact) }
                if g.contains(q) { return max(best, Weight.genreContain) }
                return best
            }
            total += genreScore
        }

        // Tags — take the single best matching tag.
        if let tags = item.tags, !tags.isEmpty {
            let tagScore = tags.reduce(0) { best, tag in
                let t = tag.lowercased()
                if t == q { return max(best, Weight.tagExact) }
                if t.contains(q) { return max(best, Weight.tagContain) }
                return best
            }
            total += tagScore
        }

        return total
    }

    /// Score an episode: check episode title and series name.
    /// Episodes intentionally score lower than genre/tag matches on a parent show,
    /// so a search like "comedy" won't flood results with every episode of comedy shows.
    private func scoreEpisode(_ item: BaseItemDto, query q: String) -> Int {
        var total = 0

        // Episode title.
        let episodeTitle = (item.name ?? "").lowercased()
        if !episodeTitle.isEmpty {
            if episodeTitle == q {
                total += Weight.episodeExact
            } else if episodeTitle.contains(q) {
                total += Weight.episodeContain
            }
        }

        // Series name — for "I remember the show but not the episode title" searches.
        let seriesName = (item.seriesName ?? "").lowercased()
        if !seriesName.isEmpty && seriesName.contains(q) {
            total += Weight.episodeSeriesContain
        }

        return total
    }
}
