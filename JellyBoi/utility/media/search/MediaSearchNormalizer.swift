//
//  MediaSearchNormalizer.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 9/7/26.
//

import Foundation

/// Text normalization and tokenization helpers shared by the search index, the scorer, and the
/// on-device query interpreter.
///
/// Every helper is a pure function, so the normalizer is safe to call from any isolation domain.
nonisolated enum MediaSearchNormalizer {

    /// Common English filler words that carry little signal in a title search.
    private static let stopWords: Set<String> = [
        "the", "a", "an", "of", "and", "in", "to", "for", "on", "with", "at", "by", "from"
    ]

    /// Normalizes a string: folds diacritics (é -> e), converts to lowercase, and trims whitespace.
    static func normalize(_ string: String) -> String {
        string
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Splits normalized text into alphanumeric tokens, stripping punctuation and symbols.
    static func tokenize(_ string: String) -> [String] {
        var tokens: [String] = []
        tokens.reserveCapacity(8)
        var current = ""

        for char in string {
            if char.isLetter || char.isNumber {
                current.append(char)
            } else if !current.isEmpty {
                tokens.append(current)
            }
        }
        if !current.isEmpty {
            tokens.append(current)
        }
        return tokens
    }

    /// Strips non-alphanumeric characters to create a compact lookup key.
    /// E.g. "Spider-Man: No Way Home" -> "spidermannowayhome"
    static func compact(_ string: String) -> String {
        string.filter { $0.isLetter || $0.isNumber }
    }

    /// Strips leading English articles ("the ", "a ", "an ") from a normalized string.
    static func stripLeadingArticle(_ string: String) -> String {
        if string.hasPrefix("the ") {
            return String(string.dropFirst(4))
        } else if string.hasPrefix("a ") {
            return String(string.dropFirst(2))
        } else if string.hasPrefix("an ") {
            return String(string.dropFirst(3))
        }
        return string
    }

    /// Generates potential acronyms for a title (e.g. "lotr" for "The Lord of the Rings").
    static func generateAcronyms(tokens: [String]) -> [String] {
        guard tokens.count >= 2, tokens.count <= 10 else { return [] }

        var results: [String] = []

        // Full acronym (every word's initial)
        let full = String(tokens.compactMap(\.first))
        if full.count >= 2 {
            results.append(full)
        }

        // Acronym without leading articles
        let withoutLeadingArticle = tokens.first.map { ["the", "a", "an"].contains($0) } == true
            ? Array(tokens.dropFirst())
            : tokens

        if withoutLeadingArticle.count != tokens.count && withoutLeadingArticle.count >= 2 {
            let acr = String(withoutLeadingArticle.compactMap(\.first))
            if !results.contains(acr) {
                results.append(acr)
            }
        }

        // Acronym of significant words only (dropping stop words like "of", "the", "and")
        let significant = withoutLeadingArticle.filter { !stopWords.contains($0) }
        if significant.count >= 2 && significant.count != withoutLeadingArticle.count {
            let acr = String(significant.compactMap(\.first))
            if !results.contains(acr) {
                results.append(acr)
            }
        }

        return results
    }

    /// Fast single-pass check if two strings have a Levenshtein edit distance <= 1.
    /// Allocates zero heap memory.
    static func isEditDistanceWithinOne(_ s1: String, _ s2: String) -> Bool {
        let count1 = s1.count
        let count2 = s2.count
        if abs(count1 - count2) > 1 { return false }

        var i1 = s1.startIndex
        var i2 = s2.startIndex
        var differences = 0

        while i1 < s1.endIndex && i2 < s2.endIndex {
            if s1[i1] != s2[i2] {
                differences += 1
                if differences > 1 { return false }

                if count1 > count2 {
                    i1 = s1.index(after: i1)
                    continue
                } else if count2 > count1 {
                    i2 = s2.index(after: i2)
                    continue
                }
            }
            i1 = s1.index(after: i1)
            i2 = s2.index(after: i2)
        }
        return true
    }
}
