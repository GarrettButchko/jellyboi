//
//  PlaybackStreamResolver.swift
//  JellyBoi
//

import Foundation
import Get
import JellyfinAPI
import LoggingKit

/// Decides how Jellyfin should deliver an item and turns that decision into a playable URL.
///
/// The server is the only authority on delivery method (direct play vs. remux vs. transcode), so
/// every non-local playback attempt starts with a `PlaybackInfo` negotiation. When the server does
/// not hand back a transcoding URL the item is directly playable and this resolver builds the
/// stream URL itself.
///
/// The resolver only decides *what* to play; authentication and `AVPlayerItem` construction are
/// left to the caller.
@MainActor
struct PlaybackStreamResolver {

    /// The server's answer, normalised into something AVPlayer can be pointed at.
    struct Resolution {
        /// Absolute URL of the stream.
        let url: URL
        /// How the server is delivering this stream.
        let playMethod: PlayMethod
        /// Session ID used by the server to track this stream.
        let sessionID: String
        /// Authoritative source info reported by the server, when it reported one.
        let mediaSource: MediaSourceInfo?
    }

    /// Reasons a stream could not be resolved. Messages are user-facing.
    enum Failure: LocalizedError {
        case noCompatibleMediaSource
        case streamURLUnavailable

        var errorDescription: String? {
            switch self {
            case .noCompatibleMediaSource:
                return "No compatible media source found."
            case .streamURLUnavailable:
                return "Unable to construct stream URL."
            }
        }
    }

    let client: JellyfinClient
    let userID: String?
    let request: PlaybackRequest

    /// Negotiates delivery with the server, falling back to a client-built stream URL when the
    /// server reported no transcoding URL.
    func resolve(itemID: String, resumeTicks: Int) async throws -> Resolution {
        let negotiation = await requestPostedPlaybackInfo(itemID: itemID, resumeTicks: resumeTicks)
        try Task.checkCancellation()

        if let url = negotiation.url {
            return Resolution(
                url: url,
                playMethod: negotiation.playMethod,
                sessionID: negotiation.sessionID ?? UUID().uuidString,
                mediaSource: negotiation.source
            )
        }

        return try resolveFallbackStream(
            itemID: itemID,
            sessionID: negotiation.sessionID,
            resumeTicks: resumeTicks,
            selectedSource: negotiation.source
        )
    }

    // MARK: - Server Negotiation

    /// Asks the server how this item should be delivered and converts the answer into a stream URL.
    ///
    /// Two outcomes are normal:
    ///   - A `transcodingURL` comes back: the server already decided to remux/transcode, and that URL
    ///     is used as-is.
    ///   - No `transcodingURL` comes back: the file is directly playable, so `url` stays nil and the
    ///     caller resolves the stream itself via `resolveFallbackStream`.
    /// `source` is returned whenever the server reports one, even if no URL was produced, because the
    /// fallback path needs it to pick between direct play and an HLS remux.
    private func requestPostedPlaybackInfo(
        itemID: String,
        resumeTicks: Int
    ) async -> (url: URL?, sessionID: String?, source: MediaSourceInfo?, playMethod: PlayMethod) {
        // A user-selected bitrate is an explicit quality request, which cannot be satisfied by direct
        // play or direct stream: the server has to transcode to hit that target. Choosing "Original"
        // leaves `maxBitrate` nil, which is what permits direct play.
        let targetBitrate: Int? = request.maxBitrate
        let allowDirect = request.maxBitrate == nil

        // Deliberately high ceiling for the "Original" case so the server never throttles on its own;
        // the real cap only matters when the user picked a preset.
        let effectiveMaxBitrate = targetBitrate ?? 140_000_000

        // Negotiation payload. The device profile advertises which containers/codecs AVPlayer can
        // handle, while the stream indices, source ID, and resume ticks tell the server exactly which
        // variant of the file to prepare.
        let playbackDto = PlaybackInfoDto(
            allowAudioStreamCopy: true,
            allowVideoStreamCopy: allowDirect,
            audioStreamIndex: request.audioStreamIndex,
            deviceProfile: JellyfinDeviceProfile.appleNative,
            enableDirectPlay: allowDirect,
            enableDirectStream: allowDirect,
            enableTranscoding: true,
            maxStreamingBitrate: effectiveMaxBitrate,
            mediaSourceID: request.mediaSourceID,
            startTimeTicks: resumeTicks,
            subtitleStreamIndex: request.subtitleStreamIndex,
            userID: userID
        )

        // Outputs, filled in from the server response below. Remaining nil means "server offered no
        // instructions for this", which the caller treats as a direct-play request.
        var streamURL: URL?                    // Set only when the server returned a transcoding URL.
        var sessionID: String?                 // Session ID used by the server to track this stream.
        var selectedSource: MediaSourceInfo?   // Authoritative source info: container, bitrate, streams.
        var playMethod: PlayMethod = .directStream // Overwritten only when transcoding is involved.

        do {
            // POST /Items/{itemID}/PlaybackInfo: the negotiation itself.
            let playbackInfo = try await client.send(
                Paths.getPostedPlaybackInfo(
                    itemID: itemID,
                    parameters: .init(userID: userID, maxStreamingBitrate: effectiveMaxBitrate),
                    playbackDto
                )
            ).value

            // Keep the server's session ID so later start/progress/stop reports match this stream.
            sessionID = playbackInfo.playSessionID

            // Honour the source the user picked when one exists; otherwise take the server's first
            // entry, which is its "Auto" choice for the item.
            let matchingSource = playbackInfo.mediaSources?.first(where: { $0.id == request.mediaSourceID })
                ?? playbackInfo.mediaSources?.first

            if let first = matchingSource {
                selectedSource = first

                // The server attaches a transcoding URL only when it decided the file cannot be sent
                // as-is. No URL means "direct play is fine", so leave `streamURL` nil for the fallback.
                if let transURL = first.transcodingURL, !transURL.isEmpty {
                    // Record which of the two server-side options was chosen so the player and the UI
                    // can report it accurately.
                    if request.maxBitrate != nil {
                        playMethod = .transcode
                    } else if first.isSupportsDirectStream == true {
                        playMethod = .directStream
                    } else {
                        playMethod = .transcode
                    }

                    // The server's URL does not always carry the requested bitrate cap, and when it
                    // does carry one it may not be the value the user picked. Force it so the quality
                    // selection is actually honoured instead of best-effort.
                    let cappedURL = PlaybackURL.applyingBitrateCap(request.maxBitrate, to: transURL)

                    // Convert the server-relative path into an absolute URL on this server.
                    streamURL = PlaybackURL.resolved(cappedURL, client: client)
                    AppLogger.info("Using server-provided transcoding URL: \(streamURL?.absoluteString ?? cappedURL)")
                }
            }
        } catch is CancellationError {
            // Preparation was abandoned (item changed or view dismissed), so this is expected and
            // should not surface as a playback failure.
            AppLogger.debug("Player preparation cancelled during getPostedPlaybackInfo")
        } catch {
            // Any other failure leaves the outputs untouched, so the caller falls back to
            // `resolveFallbackStream`. Logged at warning level because that path is less reliable.
            if !Task.isCancelled {
                AppLogger.warning("Failed to get posted playback info: \(error.localizedDescription)")
            }
        }

        // `url` may legitimately be nil on success (direct play); `source` is what the caller needs then.
        return (streamURL, sessionID, selectedSource, playMethod)
    }

    // MARK: - Client-Built Stream URLs

    /// Builds a stream URL when the server reported no transcoding URL.
    ///
    /// Apple-native containers that the server says it can send untouched get the direct static
    /// stream; everything else goes through the HLS remux/transcode endpoint.
    private func resolveFallbackStream(
        itemID: String,
        sessionID: String?,
        resumeTicks: Int,
        selectedSource: MediaSourceInfo?
    ) throws -> Resolution {
        let source = selectedSource ?? request.item.mediaSources?.first
        let container = source?.container?.lowercased() ?? ""
        let isAppleNativeContainer = ApplePlayableContainer.supports(container)
        let hasCustomStreams = request.audioStreamIndex != nil
            || (request.subtitleStreamIndex ?? -1) >= 0
            || request.maxBitrate != nil
        let canDirectPlay = source?.isSupportsDirectPlay == true && isAppleNativeContainer && !hasCustomStreams

        if canDirectPlay {
            AppLogger.info("Media container is '\(container)'; using direct static stream")
            guard let directURL = client.directVideoStreamURL(
                itemID: itemID,
                sessionID: sessionID,
                mediaSourceID: source?.id
            ) else {
                AppLogger.error("Failed to construct direct stream URL for item \(itemID)")
                throw Failure.streamURLUnavailable
            }
            return Resolution(
                url: directURL,
                playMethod: .directPlay,
                sessionID: sessionID ?? UUID().uuidString,
                mediaSource: source
            )
        } else if let validSource = source {
            let playMethod: PlayMethod = (request.maxBitrate != nil) ? .transcode : .directStream
            AppLogger.info("Container '\(container)' requires HLS remuxing/transcoding for AVPlayer; requesting master.m3u8")
            let sourceID = validSource.id ?? request.mediaSourceID ?? itemID
            let sid = sessionID ?? UUID().uuidString
            var hlsPath = "/Videos/\(itemID)/master.m3u8?MediaSourceId=\(sourceID)&PlaySessionId=\(sid)&VideoCodec=h264,hevc&AudioCodec=aac,mp3,ac3,eac3&TranscodingMaxAudioChannels=6&SegmentContainer=mp4&MinSegments=1&BreakOnNonKeyFrames=True&StartTimeTicks=\(resumeTicks)"
            if let audioIndex = request.audioStreamIndex {
                hlsPath += "&AudioStreamIndex=\(audioIndex)"
            }
            if let subtitleIndex = request.subtitleStreamIndex {
                hlsPath += "&SubtitleStreamIndex=\(subtitleIndex)"
            }
            // Same cap logic as the server-provided URL path, kept in one place.
            hlsPath = PlaybackURL.applyingBitrateCap(request.maxBitrate, to: hlsPath)
            guard let hlsURL = PlaybackURL.resolved(hlsPath, client: client) else {
                AppLogger.error("Failed to construct HLS stream URL for item \(itemID)")
                throw Failure.streamURLUnavailable
            }
            return Resolution(
                url: hlsURL,
                playMethod: playMethod,
                sessionID: sid,
                mediaSource: validSource
            )
        } else {
            AppLogger.error("Cannot resolve stream URL: no media source available")
            throw Failure.noCompatibleMediaSource
        }
    }
}
