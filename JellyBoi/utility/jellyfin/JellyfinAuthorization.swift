//
//  JellyfinAuthorization.swift
//  JellyBoi
//

import AVFoundation
import JellyfinAPI

/// Jellyfin credentials shared by streaming and download requests.
///
/// Both paths need the same `MediaBrowser` header and, for media assets, the legacy
/// `X-Emby-Token` field that AVFoundation forwards to the server.
nonisolated enum JellyfinAuthorization {

    /// `MediaBrowser` authorization header carrying this client's device identity and access token.
    static func header(for client: JellyfinClient) -> String {
        var rawFields = [
            "DeviceId": client.configuration.deviceID,
            "Device": client.configuration.deviceName,
            "Client": client.configuration.client,
            "Version": client.configuration.version,
        ]
        if let token = client.configuration.accessToken {
            rawFields["Token"] = token
        }
        let fields = rawFields.map { "\($0.key)=\"\($0.value)\"" }.joined(separator: ", ")
        return "MediaBrowser \(fields)"
    }

    /// An `AVURLAsset` that sends Jellyfin credentials with every media request.
    static func asset(url: URL, client: JellyfinClient) -> AVURLAsset {
        var headers: [String: String] = [
            "Authorization": header(for: client)
        ]
        if let token = client.configuration.accessToken {
            headers["X-Emby-Token"] = token
        }
        return AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
    }
}
