//
//  PlayerViewModel+Preparation.swift
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

    // Two ways a When requesting playback info, the Jellyfin server's transcodingURL can be returned either as:
    // 1: A full absolute URL (e.g. https://jellyfin.local:8096/videos/.../master.m3u8 when behind certain reverse proxies or base URL configurations).
    // 2: A relative path (e.g. /videos/.../master.m3u8).
    func resolveServerURL(path: String, client: JellyfinClient) -> URL? {
        if path.hasPrefix("http://") || path.hasPrefix("https://") {
            return URL(string: path)
        }
        return client.url(path: path)
    }

    // Key for jellyfin server to give video
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

    // MARK: - Player Preparation

    func prepare(mode: PlaybackPreparationMode = .immediate) async -> Bool {
        guard status != .ended else {
            AppLogger.warning("Aborted player preparation: already cleaned up")
            return false
        }
        guard !Task.isCancelled else { return false }

        status = (mode == .preload) ? .preloading : .preparing
        hasAppliedInitialSeek = false
        AppLogger.info("Starting player preparation for '\(request.item.playbackTitle)' (mode: \(mode))")

        if mode == .immediate {
            await configureAudioSession()
        }

        await resolveQueueIfNeeded()
        guard !Task.isCancelled else { return false }

        guard let prepared = await prepareMediaItem(for: request) else {
            if Task.isCancelled {
                return false
            }
            if case .failed = status {
                // Keep the specific failure reason already set
            } else {
                status = .failed(reason: "Failed to prepare media item.")
            }
            return false
        }

        guard !Task.isCancelled else { return false }

        applyPreparedMedia(prepared)

        let avPlayer = createConfiguredPlayer(for: prepared.playerItem)
        self.player = avPlayer

        startAsyncArtworkFetchIfNeeded()
        attachPlayerObservers(to: avPlayer)
        observeItemDidPlayToEnd(for: prepared.playerItem)

        let isReady = await waitForReadinessWithRetries(
            player: avPlayer,
            prepared: prepared
        )

        guard !Task.isCancelled else { return false }

        if isReady {
            status = .ready
        } else if case .failed = status {
            // Keep the specific failure reason
        } else {
            status = .failed(reason: "Playback connection timed out. Please try again.")
        }
        return isReady
    }

    private func applyPreparedMedia(_ prepared: PreparedMedia) {
        self.streamContext = prepared.streamContext
        self.loadedArtworkImage = prepared.artworkImage
    }

    private func createConfiguredPlayer(for playerItem: AVPlayerItem) -> AVPlayer {
        let avPlayer = AVPlayer(playerItem: playerItem)
        avPlayer.allowsExternalPlayback = true
        avPlayer.usesExternalPlaybackWhileExternalScreenIsActive = true
        if status.isPreloading {
            avPlayer.rate = 0.0
        }
        return avPlayer
    }

    private func attachPlayerObservers(to avPlayer: AVPlayer) {
        var lastNonZeroVolume: Float = 1.0
        subscriptions.muteObserver = avPlayer.observe(\.isMuted, options: [.new]) { player, _ in
            if player.isMuted {
                if player.volume > 0.0 {
                    lastNonZeroVolume = player.volume
                }
                player.isMuted = false
                player.volume = lastNonZeroVolume > 0.0 ? lastNonZeroVolume : 1.0
            }
        }

        subscriptions.timeControlStatusObserver = avPlayer.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            Task { @MainActor [weak self] in
                guard let self, self.status != .ended else { return }
                switch player.timeControlStatus {
                case .playing:
                    self.status = .playing
                case .paused:
                    if self.status == .playing {
                        self.status = .paused
                    }
                case .waitingToPlayAtSpecifiedRate:
                    break
                @unknown default:
                    break
                }
            }
        }

        subscriptions.timeObserverToken = avPlayer.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 4),
            queue: .main
        ) { [weak self] time in
            guard let self else { return }
            MainActor.assumeIsolated {
                let seconds = CMTimeGetSeconds(time)
                if seconds.isFinite && seconds >= 0 {
                    if self.hasAppliedInitialSeek || self.timeline.initialResumeTicks == 0 {
                        self.timeline.currentPositionTicks = Int(seconds * 10_000_000.0)
                    }
                }
                if let dur = avPlayer.currentItem?.duration {
                    let durationSec = CMTimeGetSeconds(dur)
                    if durationSec.isFinite && durationSec > 0 {
                        self.timeline.durationTicks = Int(durationSec * 10_000_000.0)
                        if !self.hasAppliedInitialSeek && self.timeline.initialResumeTicks == 0 && !self.request.startFromBeginning {
                            if let percent = self.request.item.userData?.playedPercentage, percent > 0 {
                                let calculated = Int((Double(self.timeline.durationTicks) * percent) / 100.0)
                                self.timeline.initialResumeTicks = calculated
                                self.timeline.currentPositionTicks = calculated
                            }
                        }
                    }
                }
                self.checkUpNextTrigger(currentSeconds: seconds)
            }
        }
    }

    private func waitForReadinessWithRetries(
        player: AVPlayer,
        prepared: PreparedMedia
    ) async -> Bool {
        var activeItem = prepared.playerItem
        let maxMapRetries = 2
        let wasPreloading = status.isPreloading

        for attempt in 0...maxMapRetries {
            guard !Task.isCancelled else { return false }

            if attempt > 0 {
                AppLogger.warning("Retrying playback after map initialization timeout (attempt \(attempt + 1)/\(maxMapRetries + 1)). Waiting for server transcode cache...")
                self.status = wasPreloading ? .preloading : .preparing

                subscriptions.statusObserver?.invalidate()
                subscriptions.statusObserver = nil

                try? await Task.sleep(for: .milliseconds(800))
                guard !Task.isCancelled else { return false }

                let newItem = AVPlayerItem(asset: prepared.playerItem.asset)
                newItem.externalMetadata = prepared.playerItem.externalMetadata
                if let composition = prepared.playerItem.videoComposition {
                    newItem.videoComposition = composition
                }
                player.replaceCurrentItem(with: newItem)
                activeItem = newItem
            }

            let isReady = await waitForReadiness(playerItem: activeItem)
            guard !Task.isCancelled else { return false }

            if isReady {
                if attempt > 0 {
                    AppLogger.success("Playback recovered after retry attempt \(attempt + 1)")
                }
                return true
            }

            if !isMapTimeoutFailure(item: activeItem) {
                let errDesc = activeItem.error?.localizedDescription ?? "unknown"
                let nsErr = activeItem.error as NSError?
                let errCode = nsErr?.code ?? 0
                let errDomain = nsErr?.domain ?? "none"
                AppLogger.error("Unrecoverable playback error (code=\(errCode), domain=\(errDomain), reason=\(errDesc))")
                return false
            }
        }

        if !Task.isCancelled {
            AppLogger.error("Failed to achieve readiness after \(maxMapRetries + 1) attempts")
        }
        return false
    }

    func prepareMediaItem(for req: PlaybackManager.PlaybackRequest) async -> PreparedMedia? {
        guard let itemID = req.item.id else {
            status = .failed(reason: "Invalid media item.")
            AppLogger.error("Failed to prepare playback: Item ID is nil")
            return nil
        }
        guard !Task.isCancelled else { return nil }

        let resumeTicks: Int = {
            if req.startFromBeginning { return 0 }
            if timeline.initialResumeTicks > 0 { return timeline.initialResumeTicks }
            return req.item.resumePlaybackTicks
        }()
        if timeline.initialResumeTicks == 0 && resumeTicks > 0 {
            self.timeline.initialResumeTicks = resumeTicks
            self.timeline.currentPositionTicks = resumeTicks
        }
        var preparedItem: AVPlayerItem?
        var usedLocal = false
        var resolvedPlayMethod: PlayMethod = .directStream
        var sessionID: String?
        var selectedSource: MediaSourceInfo?
        var natSize: CGSize?

        let isLocalPlayable = req.localFileURL.map { url in
            let ext = url.pathExtension.lowercased()
            return ["mp4", "m4v", "mov"].contains(ext)
        } ?? false

        if let localURL = req.localFileURL, isLocalPlayable {
            let asset = AVURLAsset(url: localURL)
            let isPlayable = (try? await asset.load(.isPlayable)) ?? false
            if isPlayable {
                AppLogger.info("Preparing local file playback from: \(localURL.path)")
                let pItem = AVPlayerItem(asset: asset)

                if let tracks = try? await asset.loadTracks(withMediaType: .video),
                   let videoTrack = tracks.first,
                   let naturalSize = try? await videoTrack.load(.naturalSize),
                   naturalSize.width > 0, naturalSize.height > 0 {
                    natSize = naturalSize
                    let trackDAR = naturalSize.width / naturalSize.height
                    if let targetDAR = self.targetAspectRatio, abs(trackDAR - targetDAR) / targetDAR > 0.02 {
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

                        let composition = AVVideoComposition(configuration: compositionConfig)
                        pItem.videoComposition = composition
                    }
                }

                preparedItem = pItem
                resolvedPlayMethod = .directPlay
                usedLocal = true
            } else {
                AppLogger.warning("Local file at \(localURL.path) cannot be opened by AVPlayer. Falling back to server stream.")
            }
        }

        if !usedLocal, let client {
            if let localURL = req.localFileURL {
                AppLogger.warning("Downloaded file at '\(localURL.path)' is not playable natively offline. Streaming from server instead.")
            }
            var streamURL: URL?

            let targetBitrate: Int? = req.maxBitrate
            let allowDirect = req.maxBitrate == nil
            let subIndex = req.subtitleStreamIndex
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
                subtitleStreamIndex: subIndex,
                userID: userID
            )

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
                            resolvedPlayMethod = .transcode
                        } else if first.isSupportsDirectStream == true {
                            resolvedPlayMethod = .directStream
                        } else {
                            resolvedPlayMethod = .transcode
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
                return nil
            } catch {
                if Task.isCancelled {
                    return nil
                }
                AppLogger.warning("Failed to get posted playback info: \(error.localizedDescription)")
            }

            guard !Task.isCancelled else { return nil }

            if streamURL == nil {
                let source = selectedSource ?? req.item.mediaSources?.first
                let container = source?.container?.lowercased() ?? ""
                let isAppleNativeContainer = ["mp4", "m4v", "mov"].contains(container)
                let hasCustomStreams = req.audioStreamIndex != nil || (req.subtitleStreamIndex != nil && req.subtitleStreamIndex! >= 0) || req.maxBitrate != nil
                let canDirectPlay = source?.isSupportsDirectPlay == true && isAppleNativeContainer && !hasCustomStreams

                if canDirectPlay {
                    resolvedPlayMethod = .directPlay
                    AppLogger.info("Media container is '\(container)'; using direct static stream")
                    streamURL = client.directVideoStreamURL(
                        itemID: itemID,
                        sessionID: sessionID,
                        mediaSourceID: source?.id
                    )
                } else if let validSource = source {
                    resolvedPlayMethod = (req.maxBitrate != nil) ? .transcode : .directStream
                    AppLogger.info("Container '\(container)' requires HLS remuxing/transcoding for AVPlayer; requesting master.m3u8")
                    let sourceID = validSource.id ?? req.mediaSourceID ?? itemID
                    let sid = sessionID ?? UUID().uuidString
                    sessionID = sid
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
                    streamURL = resolveServerURL(path: hlsPath, client: client)
                } else {
                    status = .failed(reason: "No compatible media source found.")
                    AppLogger.error("Cannot resolve stream URL: no media source available")
                    return nil
                }
            }

            guard var url = streamURL else {
                status = .failed(reason: "Unable to construct stream URL.")
                AppLogger.error("Failed to construct stream URL for item \(itemID)")
                return nil
            }

            if let token = client.configuration.accessToken,
               var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                var queryItems = components.queryItems ?? []
                if !queryItems.contains(where: { $0.name == "api_key" }) {
                    queryItems.append(URLQueryItem(name: "api_key", value: token))
                    components.queryItems = queryItems
                    if let updatedURL = components.url {
                        url = updatedURL
                    }
                }
            }

            AppLogger.info("Resolved streaming URL: \(url.absoluteString)")
            var headers: [String: String] = [
                "Authorization": authorizationHeader(for: client)
            ]
            if let token = client.configuration.accessToken {
                headers["X-Emby-Token"] = token
            }

            let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
            preparedItem = AVPlayerItem(asset: asset)
        } else if !usedLocal {
            let reason: String
            if let localURL = req.localFileURL, !isLocalPlayable {
                reason = "This video is downloaded in .\(localURL.pathExtension.uppercased()) format, which iOS cannot play offline. Please connect to your server to stream or re-download as MP4."
            } else if req.localFileURL != nil {
                reason = "The downloaded file could not be opened and server connection is unavailable."
            } else {
                reason = "Server connection is unavailable."
            }
            status = .failed(reason: reason)
            AppLogger.error("Failed to start playback: \(reason)")
            return nil
        }

        guard let playerItem = preparedItem else {
            status = .failed(reason: "Failed to initialize player item.")
            return nil
        }

        let artwork = loadCachedArtwork(for: req.item)
        let meta = createMetadata(for: req.item, artworkData: artwork?.0)
        playerItem.externalMetadata = meta

        let streamCtx = ActiveStreamContext(
            playSessionID: sessionID,
            mediaSourceID: selectedSource?.id,
            mediaSource: selectedSource,
            maxBitrate: req.maxBitrate,
            videoNaturalSize: natSize,
            playMethod: resolvedPlayMethod
        )

        return PreparedMedia(
            request: req,
            playerItem: playerItem,
            streamContext: streamCtx,
            artworkImage: artwork?.1
        )
    }

    // MARK: - Readiness & Initial Playback

    nonisolated final class ReadinessBox: @unchecked Sendable {
        private var resumed = false
        private var resumeClosure: ((Bool) -> Void)?
        private let lock = NSLock()

        func setResume(_ closure: @escaping (Bool) -> Void) {
            lock.lock()
            defer { lock.unlock() }
            resumeClosure = closure
        }

        func resume(returning value: Bool) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard !resumed, let closure = resumeClosure else { return false }
            resumed = true
            resumeClosure = nil
            closure(value)
            return true
        }
    }

    func waitForReadiness(playerItem: AVPlayerItem) async -> Bool {
        if playerItem.status == .readyToPlay {
            await applyReadyToPlay()
            return true
        }
        if playerItem.status == .failed {
            let err = playerItem.error?.localizedDescription ?? "Playback failed."
            self.status = .failed(reason: err)
            return false
        }

        let box = ReadinessBox()

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                box.setResume { val in
                    continuation.resume(returning: val)
                }

                subscriptions.statusObserver = playerItem.observe(\.status, options: [.initial, .new]) { [weak self] currentItem, _ in
                    Task { @MainActor [weak self] in
                        guard let self, !Task.isCancelled else { return }
                        switch currentItem.status {
                        case .readyToPlay:
                            AppLogger.success("PlayerItem is readyToPlay.")
                            await self.applyReadyToPlay()
                            _ = box.resume(returning: true)

                        case .failed:
                            guard !Task.isCancelled else {
                                _ = box.resume(returning: false)
                                return
                            }
                            if box.resume(returning: false) {
                                let err = currentItem.error?.localizedDescription ?? "Playback failed."
                                AppLogger.error("PlayerItem failed with error: \(err)")
                                if let log = currentItem.errorLog() {
                                    for event in log.events {
                                        AppLogger.error("AVPlayerItem error event: URI=\(event.uri ?? "nil"), status=\(event.errorStatusCode), domain=\(event.errorDomain), comment=\(event.errorComment ?? "nil")")
                                    }
                                }
                                self.status = .failed(reason: err)
                            }

                        case .unknown:
                            break
                        @unknown default:
                            break
                        }
                    }
                }
            }
        } onCancel: {
            _ = box.resume(returning: false)
        }
    }

    func isMapTimeoutFailure(item: AVPlayerItem) -> Bool {
        if let nsError = item.error as NSError? {
            if nsError.domain == "CoreMediaErrorDomain" && nsError.code == -12889 {
                return true
            }
        }
        if let log = item.errorLog() {
            for event in log.events {
                if event.errorStatusCode == -12889 {
                    return true
                }
                if let comment = event.errorComment, comment.localizedCaseInsensitiveContains("map") {
                    return true
                }
            }
        }
        return false
    }

    func applyInitialResumeSeekIfNeeded(logContext: String = "") async {
        guard !hasAppliedInitialSeek else { return }
        hasAppliedInitialSeek = true
        guard timeline.initialResumeTicks > 0 else { return }

        let seconds = timeline.initialResumeSeconds
        let currentSec = CMTimeGetSeconds(player?.currentTime() ?? .zero)

        if abs(currentSec - seconds) > 2.0 {
            let label = logContext.isEmpty ? "Seeking" : "Seeking \(logContext)"
            AppLogger.info("\(label) to resume position: \(String(format: "%.1f", seconds))s (ticks: \(timeline.initialResumeTicks))")
            let targetTime = CMTime(seconds: seconds, preferredTimescale: 600)
            let tolerance = CMTime(seconds: 0.5, preferredTimescale: 600)
            await player?.seek(to: targetTime, toleranceBefore: tolerance, toleranceAfter: tolerance)
        }
        timeline.currentPositionTicks = timeline.initialResumeTicks
    }

    func applyReadyToPlay() async {
        let wasPreloading = status.isPreloading
        self.status = .ready
        if let current = self.player?.currentItem {
            let tracks = current.tracks
            let trackInfo = tracks.map { track -> String in
                let mediaType = track.assetTrack?.mediaType.rawValue ?? "unknown"
                return "\(mediaType) (isEnabled: \(track.isEnabled))"
            }
            AppLogger.info("PlayerItem ready with \(tracks.count) tracks: [\(trackInfo.joined(separator: ", "))]")

            let videoTracks = tracks.filter { $0.assetTrack?.mediaType == .video }
            if videoTracks.isEmpty {
                AppLogger.warning("PlayerItem has NO video tracks active. PresentationSize: \(current.presentationSize)")
            } else {
                for vt in videoTracks {
                    let size = (try? await vt.assetTrack?.load(.naturalSize)) ?? .zero
                    AppLogger.debug("Video track enabled: \(vt.isEnabled), size: \(size.width)x\(size.height)")
                }
            }

            if self.streamContext.videoNaturalSize == nil, let firstVideoTrack = videoTracks.compactMap({ $0.assetTrack }).first {
                if let size = try? await firstVideoTrack.load(.naturalSize), size.width > 0, size.height > 0 {
                    self.streamContext.videoNaturalSize = size
                }
            }

            await selectRequestedSubtitle(in: current)
        }
        await applyInitialResumeSeekIfNeeded()

        self.player?.rate = 0.0
        if wasPreloading {
            AppLogger.info("Preloaded media item is paused at resume position and ready to play")
            return
        }

        AppLogger.info("Media item is prepared and paused awaiting presentation")
    }

    func startPlaybackIfNeeded() async {
        guard status != .ended, status != .playing, let player = self.player else { return }
        AppLogger.info("Starting playback on view appearance for '\(request.item.playbackTitle)'")

        await configureAudioSession()

        player.play()
        self.status = .playing
        if let img = loadedArtworkImage {
            updateNowPlayingInfo(with: img)
        }
        if !self.hasReportedStart {
            self.hasReportedStart = true
            await self.reportPlaybackStart()
            self.startPeriodicReporting()
        }
    }
}
