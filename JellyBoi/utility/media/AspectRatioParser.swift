//
//  AspectRatioParser.swift
//  JellyBoi
//

import Foundation

/// Parses the aspect ratio strings Jellyfin reports.
///
/// Jellyfin is inconsistent here: metadata may contain `"16:9"`, `"1.78:1"`, or a plain decimal
/// such as `"1.78"`. Everything that consumes a display aspect ratio goes through this parser so
/// the accepted formats stay consistent between playback and downloads.
nonisolated enum AspectRatioParser {

    /// Returns the ratio as width divided by height, or `nil` when `raw` is missing or malformed.
    static func parse(_ raw: String?) -> Double? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        if raw.contains(":") {
            let parts = raw.split(separator: ":")
            if parts.count == 2, let num = Double(parts[0]), let den = Double(parts[1]), den > 0 {
                return num / den
            }
        }
        if raw.contains("/") {
            let parts = raw.split(separator: "/")
            if parts.count == 2, let num = Double(parts[0]), let den = Double(parts[1]), den > 0 {
                return num / den
            }
        }
        if let val = Double(raw), val > 0 {
            return val
        }
        return nil
    }
}
