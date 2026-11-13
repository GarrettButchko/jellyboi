//
//  PlayerViewModel+MediaPreparation.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 10/5/26.
//

import Foundation
import CoreGraphics
import AVKit
import CoreMedia
import Get
import JellyfinAPI
import LoggingKit

extension PlayerViewModel {

    // MARK: - Device Profile

    static var appleDeviceProfile: DeviceProfile {
        DeviceProfile(
            directPlayProfiles: [
                DirectPlayProfile(
                    audioCodec: "aac,mp3,ac3,eac3,alac,flac",
                    container: ApplePlayableContainer.jellyfinContainerList,
                    type: .video,
                    videoCodec: "h264,hevc"
                ),
                DirectPlayProfile(
                    audioCodec: "aac,mp3,alac,flac,wav",
                    container: "mp3,m4a,aac,flac,wav",
                    type: .audio
                )
            ],
            maxStaticBitrate: 140_000_000,
            maxStreamingBitrate: 140_000_000,
            name: "Apple Native Player",
            subtitleProfiles: [
                SubtitleProfile(format: "vtt", method: .hls),
                SubtitleProfile(format: "webvtt", method: .hls),
                SubtitleProfile(format: "subrip", method: .hls),
                SubtitleProfile(format: "srt", method: .hls),
                SubtitleProfile(format: "ass", method: .encode),
                SubtitleProfile(format: "ssa", method: .encode)
            ],
            transcodingProfiles: [
                TranscodingProfile(
                    protocol: .hls,
                    audioCodec: "aac,mp3,ac3,eac3",
                    container: "mp4",
                    context: .streaming,
                    enableAudioVbrEncoding: true,
                    enableMpegtsM2TsMode: false,
                    enableSubtitlesInManifest: true,
                    isBreakOnNonKeyFrames: true,
                    isCopyTimestamps: true,
                    isEstimateContentLength: false,
                    maxAudioChannels: "6",
                    minSegments: 1,
                    segmentLength: 6,
                    transcodeSeekInfo: .auto,
                    type: .video,
                    videoCodec: "h264,hevc"
                ),
                TranscodingProfile(
                    protocol: .hls,
                    audioCodec: "aac,mp3,ac3,eac3",
                    container: "ts",
                    context: .streaming,
                    enableAudioVbrEncoding: true,
                    enableMpegtsM2TsMode: false,
                    enableSubtitlesInManifest: true,
                    isBreakOnNonKeyFrames: true,
                    isCopyTimestamps: true,
                    isEstimateContentLength: false,
                    maxAudioChannels: "6",
                    minSegments: 1,
                    segmentLength: 6,
                    transcodeSeekInfo: .auto,
                    type: .video,
                    videoCodec: "h264"
                ),
                TranscodingProfile(
                    protocol: .hls,
                    audioCodec: "aac,mp3",
                    container: "mp4",
                    context: .streaming,
                    enableAudioVbrEncoding: true,
                    enableMpegtsM2TsMode: false,
                    enableSubtitlesInManifest: true,
                    isBreakOnNonKeyFrames: true,
                    isCopyTimestamps: true,
                    isEstimateContentLength: false,
                    maxAudioChannels: "6",
                    minSegments: 1,
                    segmentLength: 6,
                    transcodeSeekInfo: .auto,
                    type: .audio
                )
            ]
        )
    }

    // MARK: - Server Networking Helpers

    func authorizationHeader(for client: JellyfinClient) -> String {
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

    // MARK: - Intermediate Preparation Models

    private struct LocalPreparationResult {
        let playerItem: AVPlayerItem
        let naturalSize: CGSize?
    }

    private struct ServerPreparationResult {
        let playerItem: AVPlayerItem
        let playMethod: PlayMethod
        let sessionID: String?
        let selectedSource: MediaSourceInfo?
    }

    // MARK: - Main Media Item Preparation

    func prepareMediaItem(for req: PlaybackRequest) async -> PreparedMedia? {
        guard let itemID = req.item.id else {
            now = .failed(reason: "Invalid media item.")
            AppLogger.error("Failed to prepare playback: Item ID is nil")
            return nil
        }
        guard !Task.isCancelled else { return nil }

        let resumeTicks = applyResumeTicks(for: req)
        var preparedItem: AVPlayerItem?
        var usedLocal = false
        var resolvedPlayMethod: PlayMethod = .directStream
        var sessionID: String?
        var selectedSource: MediaSourceInfo?
        var natSize: CGSize?

        // A local file only ever arrives here already vetted as a natively playable container by
        // `DownloadManager.playableLocalFileURL`; `prepareLocalPlayback` then does the real check.
        if let localURL = req.localFileURL {
            if let localResult = await prepareLocalPlayback(from: localURL) {
                preparedItem = localResult.playerItem
                natSize = localResult.naturalSize
                resolvedPlayMethod = .directPlay
                usedLocal = true
            }
        }

        if !usedLocal, let client {
            if let localURL = req.localFileURL {
                AppLogger.warning("Downloaded file at '\(localURL.path)' is not playable natively offline. Streaming from server instead.")
            }

            guard let serverResult = await prepareServerPlayback(
                for: req,
                itemID: itemID,
                resumeTicks: resumeTicks,
                client: client
            ) else {
                return nil
            }

            preparedItem = serverResult.playerItem
            resolvedPlayMethod = serverResult.playMethod
            sessionID = serverResult.sessionID
            selectedSource = serverResult.selectedSource
        } else if !usedLocal {
            handlePlaybackPreparationFailure(req: req)
            return nil
        }

        guard let playerItem = preparedItem else {
            if case .failed = now {
                // Keep specific failure reason
            } else {
                now = .failed(reason: "Failed to initialize player item.")
            }
            return nil
        }

        return makePreparedMedia(
            req: req,
            playerItem: playerItem,
            sessionID: sessionID,
            selectedSource: selectedSource,
            natSize: natSize,
            playMethod: resolvedPlayMethod
        )
    }

    // MARK: - Resume Position Setup

    private func applyResumeTicks(for req: PlaybackRequest) -> Int {
        let resumeTicks: Int = {
            if req.startFromBeginning { return 0 }
            if timeline.initialResumeTicks > 0 { return timeline.initialResumeTicks }
            return req.item.resumePlaybackTicks
        }()
        if timeline.initialResumeTicks == 0 && resumeTicks > 0 {
            self.timeline.initialResumeTicks = resumeTicks
            self.timeline.currentPositionTicks = resumeTicks
        }
        return resumeTicks
    }

    // MARK: - Local File Playback Preparation

    private func prepareLocalPlayback(from localURL: URL) async -> LocalPreparationResult? {
        let asset = AVURLAsset(url: localURL)
        let isPlayable = (try? await asset.load(.isPlayable)) ?? false
        guard isPlayable else {
            AppLogger.warning("Local file at \(localURL.path) cannot be opened by AVPlayer. Falling back to server stream.")
            return nil
        }

        AppLogger.info("Preparing local file playback from: \(localURL.path)")
        let playerItem = AVPlayerItem(asset: asset)
        var natSize: CGSize?

        if let tracks = try? await asset.loadTracks(withMediaType: .video),
           let videoTrack = tracks.first,
           let naturalSize = try? await videoTrack.load(.naturalSize),
           naturalSize.width > 0, naturalSize.height > 0 {
            natSize = naturalSize

            if let composition = await makeAspectRatioCompositionIfNeeded(for: videoTrack, naturalSize: naturalSize) {
                playerItem.videoComposition = composition
            }
        }

        return LocalPreparationResult(playerItem: playerItem, naturalSize: natSize)
    }

    private func makeAspectRatioCompositionIfNeeded(
        for videoTrack: AVAssetTrack,
        naturalSize: CGSize
    ) async -> AVVideoComposition? {
        let trackDAR = naturalSize.width / naturalSize.height
        guard let targetDAR = self.targetAspectRatio, abs(trackDAR - targetDAR) / targetDAR > 0.02 else {
            return nil
        }

        let preferredTransform = (try? await videoTrack.load(.preferredTransform)) ?? .identity
        let renderWidth = naturalSize.height * targetDAR
        let renderHeight = naturalSize.height
        let scaleX = renderWidth / naturalSize.width

        var layerConfig = AVVideoCompositionLayerInstruction.Configuration(assetTrack: videoTrack)
        let adjustedTransform = preferredTransform.scaledBy(x: scaleX, y: 1.0)
        layerConfig.setTransform(adjustedTransform, at: .zero)
        let layerInstruction = AVVideoCompositionLayerInstruction(configuration: layerConfig)

        var instructionConfig = AVVideoCompositionInstruction.Configuration()
        instructionConfig.timeRange = CMTimeRange(start: .zero, duration: .positiveInfinity)
        instructionConfig.layerInstructions = [layerInstruction]
        let instruction = AVVideoCompositionInstruction(configuration: instructionConfig)

        var compositionConfig = AVVideoComposition.Configuration()
        compositionConfig.instructions = [instruction]
        compositionConfig.renderSize = CGSize(width: renderWidth, height: renderHeight)
        let nominalFrameRate = (try? await videoTrack.load(.nominalFrameRate)) ?? 0
        let fps = nominalFrameRate > 0 ? Int32(round(nominalFrameRate)) : 30
        compositionConfig.frameDuration = CMTime(value: 1, timescale: fps)

        return AVVideoComposition(configuration: compositionConfig)
    }

    // MARK: - Server Stream Playback Preparation

    private func prepareServerPlayback(
        for req: PlaybackRequest,
        itemID: String,
        resumeTicks: Int,
        client: JellyfinClient
    ) async -> ServerPreparationResult? {
        let (streamURLFromInfo, sessionID, selectedSource, methodFromInfo) = await requestPostedPlaybackInfo(
            for: req,
            itemID: itemID,
            resumeTicks: resumeTicks,
            client: client
        )

        guard !Task.isCancelled else { return nil }

        var resolvedPlayMethod = methodFromInfo
        var resolvedStreamURL = streamURLFromInfo
        var resolvedSessionID = sessionID

        if resolvedStreamURL == nil {
            guard let fallback = resolveFallbackStream(
                for: req,
                itemID: itemID,
                sessionID: resolvedSessionID,
                resumeTicks: resumeTicks,
                selectedSource: selectedSource,
                client: client
            ) else {
                return nil
            }
            resolvedStreamURL = fallback.url
            resolvedPlayMethod = fallback.playMethod
            resolvedSessionID = fallback.sessionID
        }

        guard let finalURL = resolvedStreamURL else {
            now = .failed(reason: "Unable to construct stream URL.")
            AppLogger.error("Failed to construct stream URL for item \(itemID)")
            return nil
        }

        let authenticatedURL = PlaybackURL.appendingAuthentication(finalURL, token: client.configuration.accessToken)
        AppLogger.info("Resolved streaming URL: \(authenticatedURL.absoluteString)")

        let asset = makeAuthenticatedAsset(url: authenticatedURL, client: client)
        let playerItem = AVPlayerItem(asset: asset)

        return ServerPreparationResult(
            playerItem: playerItem,
            playMethod: resolvedPlayMethod,
            sessionID: resolvedSessionID,
            selectedSource: selectedSource
        )
    }

    /// Asks the server how this item should be delivered and converts the answer into a stream URL.
    ///
    /// The server is the only authority on delivery method (direct play vs. remux vs. transcode), so
    /// this runs before every non-local playback attempt. Two outcomes are normal:
    ///   - A `transcodingURL` comes back: the server already decided to remux/transcode, and that URL
    ///     is used as-is.
    ///   - No `transcodingURL` comes back: the file is directly playable, so `url` stays nil and the
    ///     caller resolves the stream itself via `resolveFallbackStream`.
    /// `source` is returned whenever the server reports one, even if no URL was produced, because the
    /// fallback path needs it to pick between direct play and an HLS remux.
    private func requestPostedPlaybackInfo(
        for req: PlaybackRequest,
        itemID: String,
        resumeTicks: Int,
        client: JellyfinClient
    ) async -> (url: URL?, sessionID: String?, source: MediaSourceInfo?, playMethod: PlayMethod) {
        // A user-selected bitrate is an explicit quality request, which cannot be satisfied by direct
        // play or direct stream: the server has to transcode to hit that target. Choosing "Original"
        // leaves `maxBitrate` nil, which is what permits direct play.
        let targetBitrate: Int? = req.maxBitrate
        let allowDirect = req.maxBitrate == nil

        // Deliberately high ceiling for the "Original" case so the server never throttles on its own;
        // the real cap only matters when the user picked a preset.
        let effectiveMaxBitrate = targetBitrate ?? 140_000_000

        // Negotiation payload. The device profile advertises which containers/codecs AVPlayer can
        // handle, while the stream indices, source ID, and resume ticks tell the server exactly which
        // variant of the file to prepare.
        let playbackDto = PlaybackInfoDto(
            allowAudioStreamCopy: true,
            allowVideoStreamCopy: allowDirect,
            audioStreamIndex: req.audioStreamIndex,
            deviceProfile: Self.appleDeviceProfile,
            enableDirectPlay: allowDirect,
            enableDirectStream: allowDirect,
            enableTranscoding: true,
            maxStreamingBitrate: effectiveMaxBitrate,
            mediaSourceID: req.mediaSourceID,
            startTimeTicks: resumeTicks,
            subtitleStreamIndex: req.subtitleStreamIndex,
            userID: userID
        )

        // Outputs, filled in from the server response below. Remaining nil means "server offered no
        // instructions for this", which the caller treats as a direct-play request.
        var streamURL: URL?                 // Set only when the server returned a transcoding URL.
        var sessionID: String?              // Session ID used by the server to track this stream.
        var selectedSource: MediaSourceInfo? // Authoritative source info: container, bitrate, streams.
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
            let matchingSource = playbackInfo.mediaSources?.first(where: { $0.id == req.mediaSourceID })
                ?? playbackInfo.mediaSources?.first

            if let first = matchingSource {
                selectedSource = first

                // The server attaches a transcoding URL only when it decided the file cannot be sent
                // as-is. No URL means "direct play is fine", so leave `streamURL` nil for the fallback.
                if let transURL = first.transcodingURL, !transURL.isEmpty {
                    // Record which of the two server-side options was chosen so the player and the UI
                    // can report it accurately.
                    if req.maxBitrate != nil {
                        playMethod = .transcode
                    } else if first.isSupportsDirectStream == true {
                        playMethod = .directStream
                    } else {
                        playMethod = .transcode
                    }

                    // The server's URL does not always carry the requested bitrate cap, and when it
                    // does carry one it may not be the value the user picked. Force it so the quality
                    // selection is actually honoured instead of best-effort.
                    let cappedURL = PlaybackURL.applyingBitrateCap(req.maxBitrate, to: transURL)

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

    private func resolveFallbackStream(
        for req: PlaybackRequest,
        itemID: String,
        sessionID: String?,
        resumeTicks: Int,
        selectedSource: MediaSourceInfo?,
        client: JellyfinClient
    ) -> (url: URL, playMethod: PlayMethod, sessionID: String)? {
        let source = selectedSource ?? req.item.mediaSources?.first
        let container = source?.container?.lowercased() ?? ""
        let isAppleNativeContainer = ApplePlayableContainer.supports(container)
        let hasCustomStreams = req.audioStreamIndex != nil || (req.subtitleStreamIndex != nil && req.subtitleStreamIndex! >= 0) || req.maxBitrate != nil
        let canDirectPlay = source?.isSupportsDirectPlay == true && isAppleNativeContainer && !hasCustomStreams

        if canDirectPlay {
            AppLogger.info("Media container is '\(container)'; using direct static stream")
            guard let directURL = client.directVideoStreamURL(
                itemID: itemID,
                sessionID: sessionID,
                mediaSourceID: source?.id
            ) else {
                now = .failed(reason: "Unable to construct stream URL.")
                AppLogger.error("Failed to construct direct stream URL for item \(itemID)")
                return nil
            }
            return (directURL, .directPlay, sessionID ?? UUID().uuidString)
        } else if let validSource = source {
            let playMethod: PlayMethod = (req.maxBitrate != nil) ? .transcode : .directStream
            AppLogger.info("Container '\(container)' requires HLS remuxing/transcoding for AVPlayer; requesting master.m3u8")
            let sourceID = validSource.id ?? req.mediaSourceID ?? itemID
            let sid = sessionID ?? UUID().uuidString
            var hlsPath = "/Videos/\(itemID)/master.m3u8?MediaSourceId=\(sourceID)&PlaySessionId=\(sid)&VideoCodec=h264,hevc&AudioCodec=aac,mp3,ac3,eac3&TranscodingMaxAudioChannels=6&SegmentContainer=mp4&MinSegments=1&BreakOnNonKeyFrames=True&StartTimeTicks=\(resumeTicks)"
            if let audioIndex = req.audioStreamIndex {
                hlsPath += "&AudioStreamIndex=\(audioIndex)"
            }
            if let subtitleIndex = req.subtitleStreamIndex {
                hlsPath += "&SubtitleStreamIndex=\(subtitleIndex)"
            }
            // Same cap logic as the server-provided URL path, kept in one place.
            hlsPath = PlaybackURL.applyingBitrateCap(req.maxBitrate, to: hlsPath)
            guard let hlsURL = PlaybackURL.resolved(hlsPath, client: client) else {
                now = .failed(reason: "Unable to construct stream URL.")
                AppLogger.error("Failed to construct HLS stream URL for item \(itemID)")
                return nil
            }
            return (hlsURL, playMethod, sid)
        } else {
            now = .failed(reason: "No compatible media source found.")
            AppLogger.error("Cannot resolve stream URL: no media source available")
            return nil
        }
    }

    private func makeAuthenticatedAsset(url: URL, client: JellyfinClient) -> AVURLAsset {
        var headers: [String: String] = [
            "Authorization": authorizationHeader(for: client)
        ]
        if let token = client.configuration.accessToken {
            headers["X-Emby-Token"] = token
        }
        return AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
    }

    // MARK: - Error Handling

    private func handlePlaybackPreparationFailure(req: PlaybackRequest) {
        let reason: String
        if req.localFileURL != nil {
            reason = "The downloaded file could not be opened and server connection is unavailable."
        } else {
            reason = "Server connection is unavailable."
        }
        now = .failed(reason: reason)
        AppLogger.error("Failed to start playback: \(reason)")
    }

    // MARK: - Prepared Media Assembly

    private func makePreparedMedia(
        req: PlaybackRequest,
        playerItem: AVPlayerItem,
        sessionID: String?,
        selectedSource: MediaSourceInfo?,
        natSize: CGSize?,
        playMethod: PlayMethod
    ) -> PreparedMedia {
        let artwork = loadCachedArtwork(for: req.item)
        let meta = createMetadata(for: req.item, artworkData: artwork?.0)
        playerItem.externalMetadata = meta

        let streamCtx = ActiveStreamContext(
            playSessionID: sessionID,
            mediaSourceID: selectedSource?.id,
            mediaSource: selectedSource,
            maxBitrate: req.maxBitrate,
            videoNaturalSize: natSize,
            playMethod: playMethod
        )

        return PreparedMedia(
            request: req,
            playerItem: playerItem,
            streamContext: streamCtx,
            artworkImage: artwork?.1
        )
    }
}
