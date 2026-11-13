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
/// cleans up that query string before it reaches AVPlayer.
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

    // MARK: - Authentication

    /// Returns `url` with this client's access token as `api_key`, replacing any token already there.
    ///
    /// The token is *set* rather than appended-if-missing for the same reason the bitrate cap is
    /// replaced: the server may have baked its own `api_key` into the URL, and trusting it leaves
    /// playback depending on a value this app did not choose. Setting one key also rules out the
    /// duplicate-token URLs that made the previous "only if absent" check unreliable.
    ///
    /// Comparison is case-insensitive because Jellyfin query binding is.
    static func applyingAuthentication(_ url: URL, token: String?) -> URL {
        guard let token, !token.isEmpty,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }

        let existing = components.queryItems ?? []
        var items = existing.filter { $0.name.lowercased() != "api_key" }
        items.append(URLQueryItem(name: "api_key", value: token))
        components.queryItems = items

        return components.url ?? url
    }

    // MARK: - Helpers

    /// Matches the two parameters that carry a bitrate cap, in any casing the server may emit them.
    private static func isBitrateKey(_ name: String) -> Bool {
        let key = name.lowercased()
        return key == "videobitrate" || key == "maxstreamingbitrate"
    }
}
