//
//  MediaSearchScoring.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 9/7/26.
//

import Foundation
import JellyfinAPI

// MARK: - Scoring Weights & Tiers

private enum SearchScoreTier {
    // Primary Title Signals
    static let exactTitle                = 10_000
    static let exactTitleWithoutArticle  =  9_500
    static let exactCompactTitle         =  9_000
    static let prefixTitle               =  6_000
    static let prefixTitleWithoutArticle =  5_800
    static let exactAcronym              =  5_000

    // Multi-Token Title Bonuses
    static let contiguousPhraseMatch     =  4_000
    static let orderedTokensMatch        =  3_000
    static let allTokensMatch            =  2_500

    // Individual Token Match Signals
    static let titleTokenExact           =    500
    static let titleTokenPrefix          =    300
    static let titleTokenFuzzy           =    150
    static let seriesToken               =    200
    static let genreToken                =    120
    static let tagToken                  =     80

    // Field Matches
    static let genreExactMatch           =    600
    static let genrePrefixMatch          =    350
    static let tagExactMatch             =    300

    // Metadata Bonuses
    static let yearMatch                 =  1_500
    static let favoriteBonus             =     50

    // Episode Adjustment
    static let episodeOwnTitleMatch      =  1_500
    static let episodeDampening          = -1_000
}

// MARK: - Scoring Algorithm

extension MediaSearchIndex {

    /// Scores a single candidate against the query.
    func scoreItem(
        _ item: IndexedMediaItem,
        normQuery: String,
        queryTokens: [String],
        compactQuery: String,
        detectedYear: Int?
    ) -> Int {
        var total = 0
        var matchedTitleTokenCount = 0
        var hasExactTitleMatch = false

        // 1. Exact & Prefix Title Matches
        if item.normalizedTitle == normQuery {
            total += SearchScoreTier.exactTitle
            hasExactTitleMatch = true
        } else if item.normalizedTitleWithoutArticle == normQuery {
            total += SearchScoreTier.exactTitleWithoutArticle
            hasExactTitleMatch = true
        } else if !compactQuery.isEmpty && item.compactedTitle == compactQuery {
            total += SearchScoreTier.exactCompactTitle
            hasExactTitleMatch = true
        } else if item.normalizedTitle.hasPrefix(normQuery) {
            total += SearchScoreTier.prefixTitle
        } else if item.normalizedTitleWithoutArticle.hasPrefix(normQuery) {
            total += SearchScoreTier.prefixTitleWithoutArticle
        }

        // 2. Acronym Match ("lotr", "got", etc.)
        if !hasExactTitleMatch && item.titleAcronyms.contains(normQuery) {
            total += SearchScoreTier.exactAcronym
        }

        // 3. Multi-token Title Analysis (Phrase & Token Matching)
        if !queryTokens.isEmpty && !item.titleTokens.isEmpty {
            var matchedTokenIndices: [Int] = []

            for qToken in queryTokens {
                var foundMatch = false
                for (tIdx, tToken) in item.titleTokens.enumerated() {
                    if tToken == qToken {
                        total += SearchScoreTier.titleTokenExact
                        matchedTokenIndices.append(tIdx)
                        foundMatch = true
                        break
                    } else if tToken.hasPrefix(qToken) {
                        total += SearchScoreTier.titleTokenPrefix
                        matchedTokenIndices.append(tIdx)
                        foundMatch = true
                        break
                    } else if qToken.count >= 4 && MediaSearchNormalizer.isEditDistanceWithinOne(qToken, tToken) {
                        total += SearchScoreTier.titleTokenFuzzy
                        matchedTokenIndices.append(tIdx)
                        foundMatch = true
                        break
                    }
                }
                if foundMatch {
                    matchedTitleTokenCount += 1
                }
            }

            // All tokens matched bonus
            if matchedTitleTokenCount == queryTokens.count {
                total += SearchScoreTier.allTokensMatch

                // Check if tokens appear in order
                let isOrdered = zip(matchedTokenIndices, matchedTokenIndices.dropFirst()).allSatisfy { $0 < $1 }
                if isOrdered {
                    total += SearchScoreTier.orderedTokensMatch

                    // Check contiguous phrase match (e.g. "no way home")
                    let isContiguous = zip(matchedTokenIndices, matchedTokenIndices.dropFirst()).allSatisfy { $1 == $0 + 1 }
                    if isContiguous {
                        total += SearchScoreTier.contiguousPhraseMatch
                    }
                }
            }

            // Title coverage / brevity bonus: higher density of matching tokens in the title
            let coverageRatio = Double(matchedTitleTokenCount) / Double(max(item.titleTokens.count, 1))
            total += Int(coverageRatio * 400)
        }

        // 4. Original / Alternate Title
        if let orig = item.normalizedOriginalTitle {
            if orig == normQuery {
                total += SearchScoreTier.exactTitle / 2
            } else if orig.contains(normQuery) {
                total += SearchScoreTier.titleTokenExact
            }
        }

        // 5. Year Disambiguation Bonus (e.g. "Dune 2021" vs "Dune 1984")
        if let qYear = detectedYear, let itemYear = item.year, qYear == itemYear {
            total += SearchScoreTier.yearMatch
        }

        // 6. Non-Title Fields (Genres, Tags, Series Name)
        // Check genres
        for genre in item.normalizedGenres {
            if genre == normQuery {
                total += SearchScoreTier.genreExactMatch
            } else if genre.hasPrefix(normQuery) {
                total += SearchScoreTier.genrePrefixMatch
            } else if genre.contains(normQuery) {
                total += SearchScoreTier.genreToken
            }
        }

        // Check tags
        for tag in item.normalizedTags {
            if tag == normQuery {
                total += SearchScoreTier.tagExactMatch
            } else if tag.contains(normQuery) {
                total += SearchScoreTier.tagToken
            }
        }

        // Check series name (for episodes)
        if let series = item.normalizedSeriesName {
            if series == normQuery {
                total += SearchScoreTier.exactTitle / 3
            } else if series.contains(normQuery) {
                total += SearchScoreTier.seriesToken
            }
        }

        // 7. Episode Specific Scoring
        if item.isEpisode {
            // If the query specifically matched the episode's title, reward it
            if matchedTitleTokenCount > 0 {
                total += SearchScoreTier.episodeOwnTitleMatch
            } else {
                // Otherwise apply dampening so episodes don't swamp shows and movies on broad searches
                total += SearchScoreTier.episodeDampening
            }
        }

        // 8. Subtle Tie-Breakers (Favorites & Community Rating)
        if total > 0 {
            if item.item.userData?.isFavorite == true {
                total += SearchScoreTier.favoriteBonus
            }
            if let rating = item.item.communityRating {
                total += Int(rating * 10) // +0 to +100 bonus
            }
        }

        return max(total, 0)
    }
}
