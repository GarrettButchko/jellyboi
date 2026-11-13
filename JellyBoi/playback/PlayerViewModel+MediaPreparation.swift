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
                    container: "mp4,m4v,mov",
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

    func resolveServerURL(path: String, client: JellyfinClient) -> URL? {
        if path.hasPrefix("http://") || path.hasPrefix("https://") {
            return URL(string: path)
        }
        return client.url(path: path)
    }

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

        let isLocalPlayable = isLocalPlaybackPlayable(url: req.localFileURL)

        if let localURL = req.localFileURL, isLocalPlayable {
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
            handlePlaybackPreparationFailure(req: req, isLocalPlayable: isLocalPlayable)
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

    private func isLocalPlaybackPlayable(url: URL?) -> Bool {
        guard let url else { return false }
        let ext = url.pathExtension.lowercased()
        return ["mp4", "m4v", "mov"].contains(ext)
    }

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

        let authenticatedURL = appendAuthenticationIfNeeded(to: finalURL, token: client.configuration.accessToken)
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

    private func requestPostedPlaybackInfo(
        for req: PlaybackRequest,
        itemID: String,
        resumeTicks: Int,
        client: JellyfinClient
    ) async -> (url: URL?, sessionID: String?, source: MediaSourceInfo?, playMethod: PlayMethod) {
        let targetBitrate: Int? = req.maxBitrate
        let allowDirect = req.maxBitrate == nil
        let effectiveMaxBitrate = targetBitrate ?? 140_000_000
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

        var streamURL: URL?
        var sessionID: String?
        var selectedSource: MediaSourceInfo?
        var playMethod: PlayMethod = .directStream

        do {
            let playbackInfo = try await client.send(
                Paths.getPostedPlaybackInfo(
                    itemID: itemID,
                    parameters: .init(userID: userID, maxStreamingBitrate: effectiveMaxBitrate),
                    playbackDto
                )
            ).value
            sessionID = playbackInfo.playSessionID

            let matchingSource = playbackInfo.mediaSources?.first(where: { $0.id == req.mediaSourceID })
                ?? playbackInfo.mediaSources?.first

            if let first = matchingSource {
                selectedSource = first
                if let transURL = first.transcodingURL, !transURL.isEmpty {
                    if req.maxBitrate != nil {
                        playMethod = .transcode
                    } else if first.isSupportsDirectStream == true {
                        playMethod = .directStream
                    } else {
                        playMethod = .transcode
                    }
                    var fullTransURL = transURL
                    if let maxBitrate = req.maxBitrate, !fullTransURL.contains("MaxStreamingBitrate=") {
                        let sep = fullTransURL.contains("?") ? "&" : "?"
                        fullTransURL += "\(sep)VideoBitRate=\(maxBitrate)&MaxStreamingBitrate=\(maxBitrate)"
                    }
                    streamURL = resolveServerURL(path: fullTransURL, client: client)
                    AppLogger.info("Using server-provided transcoding URL: \(streamURL?.absoluteString ?? fullTransURL)")
                }
            }
        } catch is CancellationError {
            AppLogger.debug("Player preparation cancelled during getPostedPlaybackInfo")
        } catch {
            if !Task.isCancelled {
                AppLogger.warning("Failed to get posted playback info: \(error.localizedDescription)")
            }
        }

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
        let isAppleNativeContainer = ["mp4", "m4v", "mov"].contains(container)
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
            if let maxBitrate = req.maxBitrate {
                hlsPath += "&VideoBitRate=\(maxBitrate)&MaxStreamingBitrate=\(maxBitrate)"
            }
            guard let hlsURL = resolveServerURL(path: hlsPath, client: client) else {
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

    private func appendAuthenticationIfNeeded(to url: URL, token: String?) -> URL {
        guard let token, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        var queryItems = components.queryItems ?? []
        if !queryItems.contains(where: { $0.name == "api_key" }) {
            queryItems.append(URLQueryItem(name: "api_key", value: token))
            components.queryItems = queryItems
            if let updatedURL = components.url {
                return updatedURL
            }
        }
        return url
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

    private func handlePlaybackPreparationFailure(req: PlaybackRequest, isLocalPlayable: Bool) {
        let reason: String
        if let localURL = req.localFileURL, !isLocalPlayable {
            reason = "This video is downloaded in .\(localURL.pathExtension.uppercased()) format, which iOS cannot play offline. Please connect to your server to stream or re-download as MP4."
        } else if req.localFileURL != nil {
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
