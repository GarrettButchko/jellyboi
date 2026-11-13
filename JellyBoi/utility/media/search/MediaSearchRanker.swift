//
//  MediaSearchRanker.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 9/7/26.
//

import Foundation
import JellyfinAPI

/// High-performance media search ranker utilizing an inverted token index, diacritic folding,
/// typo tolerance, acronym matching, and multi-tiered relevance scoring inspired by
/// industry-standard search engines (Spotlight, Algolia, Lucene).
///
/// Designed for low latency (< 1ms per query) and zero string allocations during interactive typing.
///
/// This type owns the caches and the public API only:
/// - text handling lives in `MediaSearchNormalizer`
/// - retrieval lives in `MediaSearchIndex`
/// - relevance lives in `MediaSearchScoring`
final class MediaSearchRanker: @unchecked Sendable {

    // MARK: - Cache & State

    private struct PoolSignature: Equatable {
        let count: Int
        let firstID: String?
        let middleID: String?
        let lastID: String?

        init(items: [BaseItemDto]) {
            self.count = items.count
            self.firstID = items.first?.id
            self.middleID = items.isEmpty ? nil : items[items.count / 2].id
            self.lastID = items.last?.id
        }
    }

    private let lock = NSLock()
    private var lastSignature: PoolSignature?
    private var index: MediaSearchIndex?
    private var lastQuery: String?
    private var lastResults: [BaseItemDto] = []

    // MARK: - Public API

    /// Returns the subset of `items` that match `query`, ordered by relevance score descending.
    ///
    /// - Parameters:
    ///   - query: The user-supplied search text. Diacritics and punctuation are folded internally.
    ///   - items: The full pool to search (movies, shows, episodes, collections).
    ///   - limit: Optional maximum number of results to return. If `nil`, all matching items are returned.
    func results(
        for query: String,
        in items: [BaseItemDto],
        limit: Int? = nil
    ) -> [BaseItemDto] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        lock.lock()
        defer { lock.unlock() }

        let signature = PoolSignature(items: items)

        // 1. Instant cache hit for identical query and identical pool
        if trimmed == lastQuery && signature == lastSignature {
            if let limit, lastResults.count > limit {
                return Array(lastResults.prefix(limit))
            }
            return lastResults
        }

        // 2. Re-index pool only when the items collection actually changes
        if index == nil || signature != lastSignature {
            index = MediaSearchIndex(items: items)
            lastSignature = signature
        }

        guard let currentIndex = index else { return [] }

        // 3. Execute indexed search
        let results = currentIndex.search(query: trimmed, limit: limit)

        lastQuery = trimmed
        lastResults = results

        return results
    }

    /// Invalidates the internal search index and query cache.
    func invalidateCache() {
        lock.lock()
        defer { lock.unlock() }
        index = nil
        lastSignature = nil
        lastQuery = nil
        lastResults = []
    }
}
