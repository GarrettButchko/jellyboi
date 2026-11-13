//
//  MediaSearchIndex.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 9/7/26.
//

import Foundation
import JellyfinAPI

// MARK: - Indexed Representation

/// A single library item flattened into the normalized strings the ranker compares against.
///
/// Normalization is expensive relative to scoring, so everything the scorer needs is computed
/// exactly once when the index is built.
struct IndexedMediaItem {
    let index: Int
    let item: BaseItemDto

    // Normalized title representations
    let normalizedTitle: String
    let normalizedTitleWithoutArticle: String
    let compactedTitle: String
    let titleTokens: [String]
    let titleAcronyms: [String]

    // Secondary metadata
    let normalizedOriginalTitle: String?
    let originalTitleTokens: [String]
    let normalizedGenres: [String]
    let genreTokens: [String]
    let normalizedTags: [String]
    let tagTokens: [String]
    let normalizedSeriesName: String?
    let seriesNameTokens: [String]

    let year: Int?
    let isEpisode: Bool
}

// MARK: - Search Index

/// Inverted index over a media pool, plus the candidate-gathering stage of the search pipeline.
///
/// Scoring lives in `MediaSearchScoring.swift`; keeping the two apart makes the retrieval and
/// relevance halves of the ranker independently readable.
final class MediaSearchIndex {

    private let items: [IndexedMediaItem]

    // Inverted Index: token -> array of item indices
    private let titleTokenPostings: [String: [Int]]
    private let otherTokenPostings: [String: [Int]]
    private let acronymPostings: [String: [Int]]

    // Sorted unique tokens for fast O(log V) prefix lookups via binary search
    private let sortedTitleTokens: [String]
    private let sortedOtherTokens: [String]

    init(items rawItems: [BaseItemDto]) {
        var indexed: [IndexedMediaItem] = []
        indexed.reserveCapacity(rawItems.count)

        var titlePostings: [String: [Int]] = [:]
        var otherPostings: [String: [Int]] = [:]
        var acrPostings: [String: [Int]] = [:]

        for (idx, item) in rawItems.enumerated() {
            let rawTitle = item.name ?? ""
            let normTitle = MediaSearchNormalizer.normalize(rawTitle)
            let titleWithoutArticle = MediaSearchNormalizer.stripLeadingArticle(normTitle)
            let compactTitle = MediaSearchNormalizer.compact(normTitle)
            let titleTokens = MediaSearchNormalizer.tokenize(normTitle)
            let acronyms = MediaSearchNormalizer.generateAcronyms(tokens: titleTokens)

            let normOrig = item.originalTitle.map { MediaSearchNormalizer.normalize($0) }
            let origTokens = normOrig.map { MediaSearchNormalizer.tokenize($0) } ?? []

            let normGenres = (item.genres ?? []).map { MediaSearchNormalizer.normalize($0) }
            var genreTokens: [String] = []
            for g in normGenres {
                genreTokens.append(contentsOf: MediaSearchNormalizer.tokenize(g))
            }

            let normTags = (item.tags ?? []).map { MediaSearchNormalizer.normalize($0) }
            var tagTokens: [String] = []
            for t in normTags {
                tagTokens.append(contentsOf: MediaSearchNormalizer.tokenize(t))
            }

            let normSeries = item.seriesName.map { MediaSearchNormalizer.normalize($0) }
            let seriesTokens = normSeries.map { MediaSearchNormalizer.tokenize($0) } ?? []

            let indexedItem = IndexedMediaItem(
                index: idx,
                item: item,
                normalizedTitle: normTitle,
                normalizedTitleWithoutArticle: titleWithoutArticle,
                compactedTitle: compactTitle,
                titleTokens: titleTokens,
                titleAcronyms: acronyms,
                normalizedOriginalTitle: normOrig,
                originalTitleTokens: origTokens,
                normalizedGenres: normGenres,
                genreTokens: genreTokens,
                normalizedTags: normTags,
                tagTokens: tagTokens,
                normalizedSeriesName: normSeries,
                seriesNameTokens: seriesTokens,
                year: item.productionYear,
                isEpisode: item.type == .episode
            )
            indexed.append(indexedItem)

            // Populate inverted index postings
            var seenTitleTokens = Set<String>()
            for token in titleTokens where seenTitleTokens.insert(token).inserted {
                titlePostings[token, default: []].append(idx)
            }

            var seenOtherTokens = Set<String>()
            for token in origTokens where seenOtherTokens.insert(token).inserted {
                otherPostings[token, default: []].append(idx)
            }
            for token in genreTokens where seenOtherTokens.insert(token).inserted {
                otherPostings[token, default: []].append(idx)
            }
            for token in tagTokens where seenOtherTokens.insert(token).inserted {
                otherPostings[token, default: []].append(idx)
            }
            for token in seriesTokens where seenOtherTokens.insert(token).inserted {
                otherPostings[token, default: []].append(idx)
            }

            for acr in acronyms {
                acrPostings[acr, default: []].append(idx)
            }
        }

        self.items = indexed
        self.titleTokenPostings = titlePostings
        self.otherTokenPostings = otherPostings
        self.acronymPostings = acrPostings
        self.sortedTitleTokens = titlePostings.keys.sorted()
        self.sortedOtherTokens = otherPostings.keys.sorted()
    }

    // MARK: - Search Execution

    func search(query: String, limit: Int?) -> [BaseItemDto] {
        let normQuery = MediaSearchNormalizer.normalize(query)
        let queryTokens = MediaSearchNormalizer.tokenize(normQuery)
        let compactQuery = MediaSearchNormalizer.compact(normQuery)

        guard !queryTokens.isEmpty || !compactQuery.isEmpty else { return [] }

        // Extract 4-digit production year if present in query (e.g. "Dune 2021")
        var detectedYear: Int?
        for token in queryTokens {
            if token.count == 4, let y = Int(token), y >= 1900, y <= 2100 {
                detectedYear = y
                break
            }
        }

        // 1. Gather candidate item indices via inverted index
        let candidateIndices = gatherCandidates(
            normQuery: normQuery,
            queryTokens: queryTokens,
            compactQuery: compactQuery
        )

        guard !candidateIndices.isEmpty else { return [] }

        // 2. Score candidate items
        var scored: [(item: BaseItemDto, score: Int, name: String)] = []
        scored.reserveCapacity(candidateIndices.count)

        for idx in candidateIndices {
            let candidate = items[idx]
            let score = scoreItem(
                candidate,
                normQuery: normQuery,
                queryTokens: queryTokens,
                compactQuery: compactQuery,
                detectedYear: detectedYear
            )
            if score > 0 {
                scored.append((candidate.item, score, candidate.item.name ?? ""))
            }
        }

        // 3. Sort by score descending, breaking ties with community rating and name
        scored.sort { lhs, rhs in
            if lhs.score != rhs.score {
                return lhs.score > rhs.score
            }
            let lhsRating = lhs.item.communityRating ?? 0
            let rhsRating = rhs.item.communityRating ?? 0
            if lhsRating != rhsRating {
                return lhsRating > rhsRating
            }
            return lhs.name < rhs.name
        }

        // 4. Return results (capped if requested)
        if let limit, scored.count > limit {
            return scored.prefix(limit).map(\.item)
        }
        return scored.map(\.item)
    }

    // MARK: - Candidate Gathering (Inverted Index)

    private func gatherCandidates(
        normQuery: String,
        queryTokens: [String],
        compactQuery: String
    ) -> Set<Int> {
        var candidates = Set<Int>()

        // Acronym match check ("lotr", "got", "bb", etc.)
        if let acrMatches = acronymPostings[normQuery] {
            candidates.formUnion(acrMatches)
        }

        // For each query token, find posting list matches
        var tokenCandidateSets: [Set<Int>] = []

        for (index, token) in queryTokens.enumerated() {
            var tokenMatches = Set<Int>()
            let isLastToken = (index == queryTokens.count - 1)

            // Exact match
            if let postings = titleTokenPostings[token] {
                tokenMatches.formUnion(postings)
            }
            if let postings = otherTokenPostings[token] {
                tokenMatches.formUnion(postings)
            }

            // Prefix match only for the token being typed. Prefix-matching every token made
            // shared words like "the" or "star" drag unrelated titles into the pool.
            if isLastToken {
                for matchingToken in matchingTokens(prefix: token, in: sortedTitleTokens) {
                    if let postings = titleTokenPostings[matchingToken] {
                        tokenMatches.formUnion(postings)
                    }
                }
                for matchingToken in matchingTokens(prefix: token, in: sortedOtherTokens) {
                    if let postings = otherTokenPostings[matchingToken] {
                        tokenMatches.formUnion(postings)
                    }
                }
            }

            // Typo / Fuzzy fallback for tokens length >= 4 if few/no matches
            if tokenMatches.count < 3 && token.count >= 4 {
                for vocabToken in sortedTitleTokens where abs(vocabToken.count - token.count) <= 1 {
                    if MediaSearchNormalizer.isEditDistanceWithinOne(token, vocabToken) {
                        if let postings = titleTokenPostings[vocabToken] {
                            tokenMatches.formUnion(postings)
                        }
                    }
                }
            }

            if !tokenMatches.isEmpty {
                tokenCandidateSets.append(tokenMatches)
            }
        }

        if !tokenCandidateSets.isEmpty {
            // For multi-word queries, first try intersection (AND match)
            if tokenCandidateSets.count > 1 {
                var intersection = tokenCandidateSets[0]
                for s in tokenCandidateSets.dropFirst() {
                    intersection.formIntersection(s)
                }
                if !intersection.isEmpty {
                    candidates.formUnion(intersection)
                }
            }

            // Also include union if candidates are sparse
            if candidates.count < 50 {
                for s in tokenCandidateSets {
                    candidates.formUnion(s)
                }
            }
        }

        // Compact match fallback (e.g. "spiderman" for "Spider-Man", "walle" for "WALL·E")
        if compactQuery.count >= 3 && candidates.count < 100 {
            for item in items {
                if item.compactedTitle.contains(compactQuery) {
                    candidates.insert(item.index)
                }
            }
        }

        return candidates
    }

    // MARK: - Binary Search Prefix Range

    private func matchingTokens(prefix: String, in vocabulary: [String]) -> [String] {
        guard !vocabulary.isEmpty, !prefix.isEmpty else { return [] }

        // Lower bound binary search
        var low = 0
        var high = vocabulary.count

        while low < high {
            let mid = (low + high) / 2
            if vocabulary[mid] < prefix {
                low = mid + 1
            } else {
                high = mid
            }
        }

        var results: [String] = []
        var i = low
        while i < vocabulary.count && vocabulary[i].hasPrefix(prefix) {
            results.append(vocabulary[i])
            i += 1
            if results.count >= 50 { break } // Bound prefix expansion
        }
        return results
    }
}
