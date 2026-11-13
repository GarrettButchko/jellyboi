//
//  PlaybackURL.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 11/13/26.
//

import Foundation
import JellyfinAPI

// MARK: - Playback URL Cleaning

/// Query-string handling for the stream URLs the Jellyfin server hands back.
///
/// The server builds transcoding and HLS URLs from its own device/transcoding profiles, so their
/// query strings arrive inconsistent: a requested bitrate cap can be missing, duplicated, or pinned
/// to a different value than the one the user picked, and keys vary in casing. Everything here
/// normalises that query string before it reaches AVPlayer.
///
/// These helpers work on server-relative paths (`/Videos/{id}/master.m3u8?...`) as well as absolute
/// URLs, so they can be applied before `resolved(_:client:)` turns the path into a real URL.
nonisolated enum PlaybackURL {

    // MARK: - Server Resolution

    /// Turns a stream path into an absolute URL on `client`'s server.
    ///
    /// Jellyfin is inconsistent here: some stream paths come back as full URLs and others as bare
    /// paths like `/Videos/{id}/master.m3u8?...`. Anything that already parses as an absolute URL is
    /// returned as-is, and everything else is resolved against the client's base address.
    static func resolved(_ path: String, client: JellyfinClient) -> URL? {
        if let url = URL(string: path), url.scheme != nil {
            return url
        }
        return client.url(path: path)
    }

    // MARK: - Bitrate Cap

    /// Forces the bitrate cap on `url` to `maxBitrate`, or returns `url` untouched when no cap was
    /// requested (`maxBitrate == nil`, meaning the user chose "Original").
    ///
    /// Both `VideoBitRate` and `MaxStreamingBitrate` are set because they mean different things:
    /// `VideoBitRate` is the video stream's target encode rate, while `MaxStreamingBitrate` caps
    /// video plus audio together. Setting only one lets the other drift above the user's choice.
    ///
    /// Any existing cap is *replaced* rather than left alone. A "skip if already present" check
    /// would trust whatever value the server baked in, which is how a user picking 4 Mbps can end
    /// up streaming at the server's profile ceiling.
    static func applyingBitrateCap(_ maxBitrate: Int?, to url: String) -> String {
        guard let maxBitrate, var components = URLComponents(string: url) else { return url }

        let existing = components.queryItems ?? []
        var items = existing.filter { !isBitrateKey($0.name) }
        items.append(URLQueryItem(name: "VideoBitRate", value: String(maxBitrate)))
        items.append(URLQueryItem(name: "MaxStreamingBitrate", value: String(maxBitrate)))
        components.queryItems = items

        return components.string ?? url
    }

    // MARK: - Query Normalisation

    /// Rebuilds the query string so each key appears exactly once, dropping a dangling `?`.
    ///
    /// When a key is repeated the **last** occurrence wins, which matches how the server resolves
    /// duplicate keys and keeps the most recently requested value.
    ///
    /// Parameters with a missing or empty value are deliberately preserved: Jellyfin uses several of
    /// them as bare flags, so stripping them to tidy up the URL can change the server's behaviour.
    static func normalised(_ url: String) -> String {
        guard var components = URLComponents(string: url) else { return url }

        guard let queryItems = components.queryItems, !queryItems.isEmpty else {
            // No query at all: remove the separator URLComponents may have kept around.
            components.query = nil
            return components.string ?? url
        }

        // Walk backwards so the final occurrence of a repeated key is the one that survives, then
        // restore the original order for readability in logs.
        var seenKeys = Set<String>()
        var kept: [URLQueryItem] = []
        for item in queryItems.reversed() where seenKeys.insert(item.name.lowercased()).inserted {
            kept.append(item)
        }

        components.queryItems = kept.reversed()
        return components.string ?? url
    }

    // MARK: - Authentication

    /// Returns `url` with the access token added as `api_key`, unless it already carries one.
    ///
    /// The token is only appended, never replaced, so a URL that already authenticates keeps working.
    /// Comparison is case-insensitive because Jellyfin query binding is.
    static func appendingAuthentication(_ url: URL, token: String?) -> URL {
        guard let token, !token.isEmpty,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }

        let existing = components.queryItems ?? []
        guard !existing.contains(where: { $0.name.lowercased() == "api_key" }) else { return url }

        components.queryItems = existing + [URLQueryItem(name: "api_key", value: token)]
        return components.url ?? url
    }

    // MARK: - Helpers

    /// Matches the two parameters that carry a bitrate cap, in any casing the server may emit them.
    private static func isBitrateKey(_ name: String) -> Bool {
        let key = name.lowercased()
        return key == "videobitrate" || key == "maxstreamingbitrate"
    }
}
