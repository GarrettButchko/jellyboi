//
//  PlayerViewModel.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 10/5/26.
//

import SwiftUI
import AVKit
import CoreMedia
import MediaPlayer
import Observation
import Get
import JellyfinAPI
import LoggingKit
import SDWebImage

@Observable
@MainActor
final class PlayerViewModel: Identifiable {

    let request: PlaybackManager.PlaybackRequest
    let client: JellyfinClient?
    let userID: String?
    weak var libraryViewModel: LibraryViewModel?

    var id: String { request.id }

    var player: AVPlayer?
    var isLoading: Bool = true
    var errorMessage: String? = nil
    var isPlaying: Bool = false

    private(set) var currentPositionTicks: Int = 0
    private(set) var durationTicks: Int = 0
    private(set) var playSessionID: String?
    private(set) var mediaSourceID: String?
    private(set) var mediaSource: MediaSourceInfo?
    private(set) var maxBitrate: Int?

    private var timeObserverToken: Any?
    private var endObserver: NSObjectProtocol?
    private var statusObserver: NSKeyValueObservation?
    private var muteObserver: NSKeyValueObservation?
    private var artworkTask: Task<Void, Never>?
    private var loadedArtworkImage: UIImage?
    private var periodicReportTimer: Timer?
    private var hasReportedStart: Bool = false
    private var isCleanedUp: Bool = false
    private var hasAppliedInitialSeek: Bool = false
    private var currentPlayMethod: PlayMethod = .directStream

    init(
        request: PlaybackManager.PlaybackRequest,
        client: JellyfinClient?,
        userID: String?,
        libraryViewModel: LibraryViewModel?
    ) {
        self.request = request
        self.client = client
        self.userID = userID
        self.libraryViewModel = libraryViewModel
        self.durationTicks = request.item.runTimeTicks.map { Int($0) } ?? 0
        self.mediaSourceID = request.mediaSourceID
        self.maxBitrate = request.maxBitrate
        AppLogger.info("Initialized PlayerViewModel for '\(request.item.name ?? "Unknown")' (ID: \(request.item.id ?? "nil"))", tag: "Player")
    }

    var item: BaseItemDto {
        request.item
    }

    var title: String {
        if item.type == .episode {
            var parts: [String] = []
            if let season = item.parentIndexNumber, let episode = item.indexNumber {
                parts.append("S\(season):E\(episode)")
            }
            if let name = item.name, !name.isEmpty {
                parts.append(name)
            }
            return parts.isEmpty ? (item.name ?? "Episode") : parts.joined(separator: " - ")
        }
        return item.name ?? "Video"
    }

    var subtitle: String? {
        if item.type == .episode {
            return item.seriesName
        }
        if let year = item.productionYear {
            return String(year)
        }
        return nil
    }

    /// Device profile representing Apple's AVPlayer capabilities (MP4/MOV direct play, HLS transcoding for MKV/etc.)
    private static var appleDeviceProfile: DeviceProfile {
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
                    segmentLength: 3,
                    transcodeSeekInfo: .auto,
                    type: .video,
                    videoCodec: "h264,hevc"
                )
            ]
        )
    }

    private func resolveServerURL(path: String, client: JellyfinClient) -> URL? {
        if path.hasPrefix("http://") || path.hasPrefix("https://") {
            return URL(string: path)
        }
        return client.url(path: path)
    }

    private func authorizationHeader(for client: JellyfinClient) -> String {
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

    /// Prepares playback asynchronously in the background.
    /// Returns true when the player item is readyToPlay, or false if preparation/stream loading failed.
    func prepare() async -> Bool {
        guard !isCleanedUp else {
            AppLogger.warning("Aborted player preparation: already cleaned up", tag: "Player")
            return false
        }
        isLoading = true
        errorMessage = nil
        hasAppliedInitialSeek = false
        AppLogger.info("Starting player preparation for '\(title)'", tag: "Player")

        // Configure audio session immediately before preparing player
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, policy: .longFormVideo)
            try await activateAudioSession()
            AppLogger.debug("Configured AVAudioSession (.playback, .moviePlayback, .longFormVideo)", tag: "Player")
        } catch {
            AppLogger.warning("Long-form video audio session policy failed: \(error.localizedDescription); falling back", tag: "Player")
            do {
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
                try await activateAudioSession()
            } catch {
                AppLogger.error("Audio session configuration failed: \(error.localizedDescription)", error, tag: "Player")
            }
        }

        guard let itemID = item.id else {
            errorMessage = "Invalid media item."
            isLoading = false
            AppLogger.error("Failed to start playback: Item ID is nil", tag: "Player")
            return false
        }

        let resumeTicks = request.startFromBeginning ? 0 : (item.userData?.playbackPositionTicks ?? 0)
        self.currentPositionTicks = resumeTicks

        let playerItem: AVPlayerItem
        if let localURL = request.localFileURL {
            AppLogger.info("Preparing local file playback from: \(localURL.path)", tag: "Player")
            playerItem = AVPlayerItem(url: localURL)
        } else if let client {
            var streamURL: URL?
            var selectedMediaSource: MediaSourceInfo?

            AppLogger.debug("Requesting playback info with Apple DeviceProfile for item \(itemID)", tag: "Player")
            let targetBitrate: Int? = request.maxBitrate
            let allowDirect = request.maxBitrate == nil
            let subIndex = request.subtitleStreamIndex
            let playbackDto = PlaybackInfoDto(
                allowAudioStreamCopy: true,
                allowVideoStreamCopy: allowDirect,
                audioStreamIndex: request.audioStreamIndex,
                deviceProfile: Self.appleDeviceProfile,
                enableDirectPlay: allowDirect,
                enableDirectStream: allowDirect,
                enableTranscoding: true,
                maxStreamingBitrate: targetBitrate,
                mediaSourceID: request.mediaSourceID,
                startTimeTicks: resumeTicks,
                subtitleStreamIndex: subIndex,
                userID: userID
            )

            do {
                let playbackInfo = try await client.send(
                    Paths.getPostedPlaybackInfo(
                        itemID: itemID,
                        parameters: .init(userID: userID, maxStreamingBitrate: targetBitrate),
                        playbackDto
                    )
                ).value
                self.playSessionID = playbackInfo.playSessionID
                AppLogger.debug("Received playback info. Session ID: \(playbackInfo.playSessionID ?? "nil")", tag: "Player")

                let matchingSource = playbackInfo.mediaSources?.first(where: { $0.id == request.mediaSourceID })
                    ?? playbackInfo.mediaSources?.first

                if let first = matchingSource {
                    selectedMediaSource = first
                    self.mediaSource = first
                    self.mediaSourceID = first.id
                    AppLogger.debug("Media source container: \(first.container ?? "unknown"), directPlay: \(first.isSupportsDirectPlay ?? false), directStream: \(first.isSupportsDirectStream ?? false), transcoding: \(first.isSupportsTranscoding ?? false)", tag: "Player")

                    if let transURL = first.transcodingURL, !transURL.isEmpty {
                        currentPlayMethod = (request.maxBitrate != nil) ? .transcode : ((first.isSupportsDirectStream == true && first.isSupportsTranscoding != true) ? .directStream : .transcode)
                        var fullTransURL = transURL
                        if let maxBitrate = request.maxBitrate, !fullTransURL.contains("MaxStreamingBitrate=") {
                            let sep = fullTransURL.contains("?") ? "&" : "?"
                            fullTransURL += "\(sep)VideoBitRate=\(maxBitrate)&MaxStreamingBitrate=\(maxBitrate)"
                        }
                        streamURL = resolveServerURL(path: fullTransURL, client: client)
                        AppLogger.info("Using server-provided transcoding URL: \(streamURL?.absoluteString ?? fullTransURL)", tag: "Player")
                    }
                }
            } catch {
                AppLogger.warning("Failed to get posted playback info: \(error.localizedDescription)", tag: "Player")
            }

            // Fallback if no server transcoding URL was returned
            if streamURL == nil {
                let container = selectedMediaSource?.container?.lowercased() ?? ""
                let isAppleNativeContainer = ["mp4", "m4v", "mov"].contains(container)
                let hasCustomStreams = request.audioStreamIndex != nil || (request.subtitleStreamIndex != nil && request.subtitleStreamIndex! >= 0) || request.maxBitrate != nil
                let canDirectPlay = selectedMediaSource?.isSupportsDirectPlay == true && isAppleNativeContainer && !hasCustomStreams

                if canDirectPlay {
                    currentPlayMethod = .directPlay
                    AppLogger.info("Media container is '\(container)'; using direct static stream", tag: "Player")
                    streamURL = client.url(
                        with: Paths.getVideoStream(
                            itemID: itemID,
                            parameters: .init(
                                isStatic: true,
                                playSessionID: self.playSessionID,
                                mediaSourceID: selectedMediaSource?.id
                            )
                        ),
                        queryAPIKey: true
                    )
                } else {
                    currentPlayMethod = (request.maxBitrate != nil) ? .transcode : .directStream
                    AppLogger.info("Container '\(container)' requires HLS remuxing/transcoding for AVPlayer; requesting master.m3u8", tag: "Player")
                    let sourceID = selectedMediaSource?.id ?? request.mediaSourceID ?? itemID
                    let sessionID = self.playSessionID ?? UUID().uuidString
                    self.playSessionID = sessionID
                    var hlsPath = "/Videos/\(itemID)/master.m3u8?MediaSourceId=\(sourceID)&PlaySessionId=\(sessionID)&VideoCodec=h264,hevc&AudioCodec=aac,mp3,ac3,eac3&TranscodingMaxAudioChannels=6&SegmentContainer=ts&MinSegments=1&BreakOnNonKeyFrames=True&StartTimeTicks=\(resumeTicks)"
                    if let audioIndex = request.audioStreamIndex {
                        hlsPath += "&AudioStreamIndex=\(audioIndex)"
                    }
                    if let subtitleIndex = request.subtitleStreamIndex {
                        hlsPath += "&SubtitleStreamIndex=\(subtitleIndex)"
                    }
                    if let maxBitrate = request.maxBitrate {
                        hlsPath += "&VideoBitRate=\(maxBitrate)&MaxStreamingBitrate=\(maxBitrate)"
                    }
                    streamURL = resolveServerURL(path: hlsPath, client: client)
                }
            }

            guard var url = streamURL else {
                let err = "Unable to construct stream URL."
                errorMessage = err
                isLoading = false
                AppLogger.error("Failed to construct stream URL for item \(itemID)", tag: "Player")
                return false
            }

            // Ensure api_key is present on the stream URL so AVPlayer HLS sub-segment requests authenticate
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

            AppLogger.info("Resolved streaming URL: \(url.absoluteString)", tag: "Player")

            var headers: [String: String] = [
                "Authorization": authorizationHeader(for: client)
            ]
            if let token = client.configuration.accessToken {
                headers["X-Emby-Token"] = token
            }

            AppLogger.debug("Creating AVURLAsset with authentication headers", tag: "Player")
            let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
            playerItem = AVPlayerItem(asset: asset)
        } else {
            errorMessage = "Server connection is unavailable."
            isLoading = false
            AppLogger.error("Failed to start playback: Jellyfin client is nil", tag: "Player")
            return false
        }

        // Configure external metadata for lock screen & AirPlay
        var meta: [AVMetadataItem] = []
        let titleItem = AVMutableMetadataItem()
        titleItem.identifier = .commonIdentifierTitle
        titleItem.value = title as (NSCopying & NSObjectProtocol)
        titleItem.extendedLanguageTag = "und"
        meta.append(titleItem)

        if let sub = subtitle {
            let artistItem = AVMutableMetadataItem()
            artistItem.identifier = .commonIdentifierArtist
            artistItem.value = sub as (NSCopying & NSObjectProtocol)
            artistItem.extendedLanguageTag = "und"
            meta.append(artistItem)

            let trackSubTitleItem = AVMutableMetadataItem()
            trackSubTitleItem.identifier = .iTunesMetadataTrackSubTitle
            trackSubTitleItem.value = sub as (NSCopying & NSObjectProtocol)
            trackSubTitleItem.extendedLanguageTag = "und"
            meta.append(trackSubTitleItem)
        }

        if let overview = request.item.overview, !overview.isEmpty {
            let descItem = AVMutableMetadataItem()
            descItem.identifier = .commonIdentifierDescription
            descItem.value = overview as (NSCopying & NSObjectProtocol)
            descItem.extendedLanguageTag = "und"
            meta.append(descItem)
        }

        if let genres = request.item.genres, !genres.isEmpty {
            let genreItem = AVMutableMetadataItem()
            genreItem.identifier = .quickTimeMetadataGenre
            genreItem.value = genres.joined(separator: ", ") as (NSCopying & NSObjectProtocol)
            genreItem.extendedLanguageTag = "und"
            meta.append(genreItem)
        }

        if let rating = request.item.officialRating, !rating.isEmpty {
            let ratingItem = AVMutableMetadataItem()
            ratingItem.identifier = .iTunesMetadataContentRating
            ratingItem.value = rating as (NSCopying & NSObjectProtocol)
            ratingItem.extendedLanguageTag = "und"
            meta.append(ratingItem)
        }

        // Load cached artwork or fetch immediately
        if let (artworkData, artworkImage) = await loadArtwork() {
            let artworkItem = AVMutableMetadataItem()
            artworkItem.identifier = .commonIdentifierArtwork
            artworkItem.dataType = kCMMetadataBaseDataType_JPEG as String
            artworkItem.value = artworkData as (NSCopying & NSObjectProtocol)
            artworkItem.extendedLanguageTag = "und"
            meta.append(artworkItem)
            self.loadedArtworkImage = artworkImage
            updateNowPlayingInfo(with: artworkImage)
        }

        playerItem.externalMetadata = meta

        let avPlayer = AVPlayer(playerItem: playerItem)
        avPlayer.allowsExternalPlayback = true
        avPlayer.usesExternalPlaybackWhileExternalScreenIsActive = true
        self.player = avPlayer

        // Start background artwork fetch if artwork was not yet available in cache
        startAsyncArtworkFetchIfNeeded()

        // Observe mute status to ensure CoreAudio/Simulator volume stays in sync
        var lastNonZeroVolume: Float = 1.0
        muteObserver = avPlayer.observe(\.isMuted, options: [.new]) { player, _ in
            if player.isMuted {
                if player.volume > 0.0 {
                    lastNonZeroVolume = player.volume
                    player.volume = 0.0
                }
            } else {
                player.volume = lastNonZeroVolume > 0.0 ? lastNonZeroVolume : 1.0
            }
        }

        // Observe playback time
        timeObserverToken = avPlayer.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 1, preferredTimescale: 1),
            queue: .main
        ) { [weak self] time in
            guard let self else { return }
            MainActor.assumeIsolated {
                let seconds = CMTimeGetSeconds(time)
                if seconds.isFinite && seconds >= 0 {
                    self.currentPositionTicks = Int(seconds * 10_000_000.0)
                }
                if let dur = avPlayer.currentItem?.duration {
                    let durationSec = CMTimeGetSeconds(dur)
                    if durationSec.isFinite && durationSec > 0 {
                        self.durationTicks = Int(durationSec * 10_000_000.0)
                    }
                }
            }
        }

        // Observe end of media
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                AppLogger.info("Playback reached end of media item", tag: "Player")
                self?.handlePlaybackFinished()
            }
        }

        // Wait for player readiness or failure (with a 30s timeout)
        let isReady = await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                await self.waitForReadiness(playerItem: playerItem)
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(30))
                return false
            }
            let firstResult = await group.next() ?? false
            group.cancelAll()
            return firstResult
        }

        if !isReady && errorMessage == nil {
            errorMessage = "Playback connection timed out. Please try again."
        }
        return isReady
    }

    private nonisolated final class ReadinessBox: @unchecked Sendable {
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

    private func waitForReadiness(playerItem: AVPlayerItem) async -> Bool {
        if playerItem.status == .readyToPlay {
            await applyReadyToPlay()
            return true
        }
        if playerItem.status == .failed {
            let err = playerItem.error?.localizedDescription ?? "Playback failed."
            self.errorMessage = err
            return false
        }

        let box = ReadinessBox()

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                box.setResume { val in
                    continuation.resume(returning: val)
                }

                statusObserver = playerItem.observe(\.status, options: [.initial, .new]) { [weak self] currentItem, _ in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        switch currentItem.status {
                        case .readyToPlay:
                            if box.resume(returning: true) {
                                AppLogger.success("PlayerItem is readyToPlay.", tag: "Player")
                                await self.applyReadyToPlay()
                            }

                        case .failed:
                            if box.resume(returning: false) {
                                let err = currentItem.error?.localizedDescription ?? "Playback failed."
                                AppLogger.error("PlayerItem failed with error: \(err)", tag: "Player")
                                if let log = currentItem.errorLog() {
                                    for event in log.events {
                                        AppLogger.error("AVPlayerItem error event: URI=\(event.uri ?? "nil"), status=\(event.errorStatusCode), domain=\(event.errorDomain), comment=\(event.errorComment ?? "nil")", tag: "Player")
                                    }
                                }
                                self.isLoading = false
                                self.errorMessage = err
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

    private func applyReadyToPlay() async {
        self.isLoading = false
        if let current = self.player?.currentItem {
            selectRequestedSubtitle(in: current)
        }
        if !self.hasAppliedInitialSeek && self.currentPositionTicks > 0 {
            self.hasAppliedInitialSeek = true
            let seconds = Double(self.currentPositionTicks) / 10_000_000.0
            let currentSec = CMTimeGetSeconds(self.player?.currentTime() ?? .zero)
            if abs(currentSec - seconds) > 2.0 {
                AppLogger.info("Seeking to resume position: \(String(format: "%.1f", seconds))s (ticks: \(self.currentPositionTicks))", tag: "Player")
                let targetTime = CMTime(seconds: seconds, preferredTimescale: 600)
                await self.player?.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero)
            }
        }
        self.player?.play()
        self.isPlaying = true
        if let img = loadedArtworkImage {
            updateNowPlayingInfo(with: img)
        }
        if !self.hasReportedStart {
            self.hasReportedStart = true
            await self.reportPlaybackStart()
            self.startPeriodicReporting()
        }
    }

    // MARK: - Subtitle Selection

    private func selectRequestedSubtitle(in playerItem: AVPlayerItem) {
        guard let group = playerItem.asset.mediaSelectionGroup(forMediaCharacteristic: .legible) else { return }

        if request.subtitleStreamIndex == -1 {
            playerItem.select(nil, in: group)
            AppLogger.debug("Deselected subtitle stream group for item (Subtitles Off)", tag: "Player")
            return
        }

        if let subIndex = request.subtitleStreamIndex, subIndex >= 0 {
            let streams = (request.item.mediaStreams ?? []) + (mediaSource?.mediaStreams ?? [])
            if let stream = streams.first(where: { $0.type == .subtitle && $0.index == subIndex }) {
                let streamLang = stream.language?.lowercased()
                if let match = group.options.first(where: { opt in
                    if let lang = streamLang, (opt.extendedLanguageTag?.lowercased() == lang || opt.locale?.identifier.lowercased().hasPrefix(lang) == true) {
                        return true
                    }
                    if let title = stream.title, opt.displayName.localizedCaseInsensitiveContains(title) {
                        return true
                    }
                    return false
                }) {
                    playerItem.select(match, in: group)
                    AppLogger.debug("Auto-selected subtitle track: \(match.displayName)", tag: "Player")
                }
            }
        }
    }

    // MARK: - Periodic Reporting

    private func startPeriodicReporting() {
        periodicReportTimer?.invalidate()
        periodicReportTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.player?.timeControlStatus != .paused else { return }
                await self.reportPlaybackProgress()
            }
        }
    }

    // MARK: - Jellyfin Session Reporting

    func reportPlaybackStart() async {
        guard let client, let itemID = item.id else { return }
        AppLogger.debug("Reporting playback start to Jellyfin (positionTicks: \(currentPositionTicks), method: \(currentPlayMethod.rawValue))", tag: "Player")
        let state = PlaybackStateInfo(
            canSeek: true,
            isPaused: false,
            itemID: itemID,
            mediaSourceID: mediaSourceID,
            playMethod: currentPlayMethod,
            playSessionID: playSessionID,
            positionTicks: currentPositionTicks
        )
        do {
            _ = try await client.send(Paths.reportPlaybackStart(state))
            AppLogger.debug("Successfully reported playback start", tag: "Player")
        } catch {
            AppLogger.warning("Failed to report playback start: \(error.localizedDescription)", tag: "Player")
        }
    }

    func reportPlaybackProgress() async {
        guard let client, let itemID = item.id else { return }
        let isPaused = player?.timeControlStatus == .paused
        let currentSeconds = Double(currentPositionTicks) / 10_000_000.0
        let totalSeconds = Double(durationTicks) / 10_000_000.0
        let percent = totalSeconds > 0 ? (currentSeconds / totalSeconds) * 100 : 0
        AppLogger.debug("Progress report: \(String(format: "%.1f", currentSeconds))s / \(String(format: "%.1f", totalSeconds))s (\(String(format: "%.1f", percent))%) [paused: \(isPaused)]", tag: "Player")

        let state = PlaybackStateInfo(
            canSeek: true,
            isPaused: isPaused,
            itemID: itemID,
            mediaSourceID: mediaSourceID,
            playMethod: currentPlayMethod,
            playSessionID: playSessionID,
            positionTicks: currentPositionTicks
        )
        do {
            _ = try await client.send(Paths.reportPlaybackProgress(state))
        } catch {
            AppLogger.warning("Failed to report playback progress: \(error.localizedDescription)", tag: "Player")
        }
        updateLocalProgress(positionTicks: currentPositionTicks)
    }

    func reportPlaybackStopped() async {
        guard let client, let itemID = item.id else { return }
        AppLogger.info("Reporting playback stopped to Jellyfin (final positionTicks: \(currentPositionTicks))", tag: "Player")
        let stopInfo = PlaybackStopInfo(
            itemID: itemID,
            mediaSourceID: mediaSourceID,
            playSessionID: playSessionID,
            positionTicks: currentPositionTicks
        )
        do {
            _ = try await client.send(Paths.reportPlaybackStopped(stopInfo))
            AppLogger.debug("Successfully reported playback stop to server", tag: "Player")
        } catch {
            AppLogger.warning("Failed to report playback stop: \(error.localizedDescription)", tag: "Player")
        }
    }

    private func handlePlaybackFinished() {
        let finalTicks = durationTicks > 0 ? durationTicks : currentPositionTicks
        currentPositionTicks = finalTicks
        AppLogger.success("Playback marked as watched (100%)", tag: "Player")
        updateLocalProgress(positionTicks: finalTicks, forcePlayed: true)
        Task {
            await reportPlaybackStopped()
        }
    }

    private func updateLocalProgress(positionTicks: Int, forcePlayed: Bool = false) {
        guard let itemID = item.id else { return }
        let total = durationTicks > 0 ? durationTicks : (item.runTimeTicks.map { Int($0) } ?? 0)
        let percent: Double = total > 0 ? (Double(positionTicks) / Double(total)) * 100.0 : 0.0
        let isPlayed = forcePlayed || percent >= 85.0

        libraryViewModel?.updateProgress(for: itemID, positionTicks: positionTicks, totalTicks: total)

        NotificationCenter.default.post(
            name: .mediaProgressUpdated,
            object: itemID,
            userInfo: [
                "positionTicks": positionTicks,
                "playedPercentage": percent,
                "isPlayed": isPlayed
            ]
        )
    }

    // MARK: - Poster Artwork & Now Playing Info

    private func resolveArtworkURLs() -> [URL] {
        guard let client else { return [] }
        var urls: [URL] = []
        let currentItem = request.item

        // 1. LibraryViewModel posterURL (matches the card / detail cache key)
        if let libURL = libraryViewModel?.posterURL(for: currentItem, client: client) {
            urls.append(libURL)
        }

        // 2. Primary image
        if let id = currentItem.id {
            if let primaryURL = client.url(with: Paths.getItemImage(
                itemID: id,
                imageType: "Primary",
                parameters: .init(maxWidth: 600, quality: 90)
            )) {
                if !urls.contains(primaryURL) {
                    urls.append(primaryURL)
                }
            }
        }

        // 3. For episodes, fallback to series or season poster
        if currentItem.type == .episode {
            if let seriesID = currentItem.seriesID {
                if let seriesURL = client.url(with: Paths.getItemImage(
                    itemID: seriesID,
                    imageType: "Primary",
                    parameters: .init(maxWidth: 600, quality: 90)
                )) {
                    if !urls.contains(seriesURL) {
                        urls.append(seriesURL)
                    }
                }
            }
            if let seasonID = currentItem.seasonID {
                if let seasonURL = client.url(with: Paths.getItemImage(
                    itemID: seasonID,
                    imageType: "Primary",
                    parameters: .init(maxWidth: 600, quality: 90)
                )) {
                    if !urls.contains(seasonURL) {
                        urls.append(seasonURL)
                    }
                }
            }
        }

        // 4. Thumb / Backdrop fallback
        if let id = currentItem.id {
            if currentItem.imageTags?.keys.contains("Thumb") == true {
                if let thumbURL = client.url(with: Paths.getItemImage(
                    itemID: id,
                    imageType: "Thumb",
                    parameters: .init(maxWidth: 600, quality: 90)
                )) {
                    if !urls.contains(thumbURL) {
                        urls.append(thumbURL)
                    }
                }
            }
            if currentItem.backdropImageTags?.isEmpty == false || currentItem.imageTags?.keys.contains("Backdrop") == true {
                if let backdropURL = client.url(with: Paths.getItemImage(
                    itemID: id,
                    imageType: "Backdrop",
                    parameters: .init(maxWidth: 800, quality: 90)
                )) {
                    if !urls.contains(backdropURL) {
                        urls.append(backdropURL)
                    }
                }
            }
        }

        return urls
    }

    private func loadArtwork(timeoutSeconds: Double = 2.5) async -> (Data, UIImage)? {
        let urls = resolveArtworkURLs()
        guard !urls.isEmpty else { return nil }

        // 1. Check SDWebImage memory or disk cache first (instant)
        for url in urls {
            let cacheKey = SDWebImageManager.shared.cacheKey(for: url) ?? url.absoluteString
            if let img = SDImageCache.shared.imageFromMemoryCache(forKey: cacheKey) ?? SDImageCache.shared.imageFromDiskCache(forKey: cacheKey) {
                if let data = img.jpegData(compressionQuality: 0.85) ?? img.pngData() {
                    AppLogger.debug("Loaded poster artwork from SDImageCache for \(title)", tag: "Player")
                    return (data, img)
                }
            }
        }

        // 2. Fetch asynchronously if not cached
        for url in urls {
            if let img = await fetchImage(for: url, timeoutSeconds: timeoutSeconds) {
                if let data = img.jpegData(compressionQuality: 0.85) ?? img.pngData() {
                    AppLogger.debug("Downloaded poster artwork for \(title)", tag: "Player")
                    return (data, img)
                }
            }
        }

        return nil
    }

    private nonisolated final class ArtworkFetchBox: @unchecked Sendable {
        private var resumed = false
        private var operation: SDWebImageOperation?
        private let lock = NSLock()

        func setOperation(_ op: SDWebImageOperation?) {
            lock.lock()
            defer { lock.unlock() }
            operation = op
        }

        func resume(with continuation: CheckedContinuation<UIImage?, Never>, image: UIImage?) {
            lock.lock()
            defer { lock.unlock() }
            guard !resumed else { return }
            resumed = true
            continuation.resume(returning: image)
        }

        func cancel() {
            lock.lock()
            let op = operation
            operation = nil
            lock.unlock()
            op?.cancel()
        }
    }

    private func fetchImage(for url: URL, timeoutSeconds: Double) async -> UIImage? {
        await withTaskGroup(of: UIImage?.self) { group in
            group.addTask {
                let box = ArtworkFetchBox()
                return await withTaskCancellationHandler {
                    await withCheckedContinuation { continuation in
                        let op = SDWebImageManager.shared.loadImage(
                            with: url,
                            options: [.highPriority, .continueInBackground],
                            progress: nil
                        ) { image, _, _, _, finished, _ in
                            if finished {
                                box.resume(with: continuation, image: image)
                            }
                        }
                        box.setOperation(op)
                        if op == nil {
                            box.resume(with: continuation, image: nil)
                        }
                    }
                } onCancel: {
                    box.cancel()
                }
            }

            group.addTask {
                try? await Task.sleep(for: .seconds(timeoutSeconds))
                return nil
            }

            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }

    private func startAsyncArtworkFetchIfNeeded() {
        guard loadedArtworkImage == nil else { return }

        artworkTask = Task { @MainActor [weak self] in
            guard let self else { return }
            if let (data, img) = await self.loadArtwork(timeoutSeconds: 8.0) {
                guard !Task.isCancelled else { return }
                self.loadedArtworkImage = img
                self.applyArtwork(data: data, image: img)
            }
        }
    }

    private func applyArtwork(data: Data, image: UIImage) {
        guard let currentItem = player?.currentItem else { return }
        var meta = currentItem.externalMetadata
        meta.removeAll { $0.identifier == .commonIdentifierArtwork }

        let artworkItem = AVMutableMetadataItem()
        artworkItem.identifier = .commonIdentifierArtwork
        artworkItem.dataType = kCMMetadataBaseDataType_JPEG as String
        artworkItem.value = data as (NSCopying & NSObjectProtocol)
        artworkItem.extendedLanguageTag = "und"
        meta.append(artworkItem)

        currentItem.externalMetadata = meta
        updateNowPlayingInfo(with: image)
        AppLogger.info("Applied poster artwork to current playerItem and MPNowPlayingInfoCenter", tag: "Player")
    }

    private func updateNowPlayingInfo(with image: UIImage?) {
        #if canImport(MediaPlayer)
        guard let image else { return }
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPMediaItemPropertyTitle] = title
        if let sub = subtitle {
            info[MPMediaItemPropertyArtist] = sub
        }
        let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        info[MPMediaItemPropertyArtwork] = artwork

        if let dur = player?.currentItem?.duration {
            let sec = CMTimeGetSeconds(dur)
            if sec.isFinite && sec > 0 {
                info[MPMediaItemPropertyPlaybackDuration] = sec
            }
        }
        if let cur = player?.currentTime() {
            let sec = CMTimeGetSeconds(cur)
            if sec.isFinite {
                info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = sec
            }
        }
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        AppLogger.debug("Updated MPNowPlayingInfoCenter artwork for \(title)", tag: "Player")
        #endif
    }

    func cleanup() {
        guard !isCleanedUp else { return }
        isCleanedUp = true
        AppLogger.info("Cleaning up PlayerViewModel resources for '\(title)'", tag: "Player")

        periodicReportTimer?.invalidate()
        periodicReportTimer = nil

        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
            timeObserverToken = nil
        }

        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }

        statusObserver?.invalidate()
        statusObserver = nil

        muteObserver?.invalidate()
        muteObserver = nil

        artworkTask?.cancel()
        artworkTask = nil
        loadedArtworkImage = nil
        #if canImport(MediaPlayer)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        #endif

        // Immediately pause and stop audio playback
        player?.pause()
        player?.rate = 0.0

        // Cancel any pending asset loading and tear down the current item
        if let currentItem = player?.currentItem {
            (currentItem.asset as? AVURLAsset)?.cancelLoading()
        }
        player?.replaceCurrentItem(with: nil)
        player = nil

        // Clear HTTP URL cache for streamed media chunks
        URLCache.shared.removeAllCachedResponses()

        // Deactivate audio session to release the audio pipeline asynchronously
        deactivateAudioSession()

        // Report stop & update final progress
        let finalTicks = currentPositionTicks
        updateLocalProgress(positionTicks: finalTicks)
        Task {
            await reportPlaybackStopped()
        }
    }

    private func activateAudioSession() async throws {
        if #available(iOS 27.0, *) {
            try await AVAudioSession.sharedInstance().activate()
        } else {
            try await Task.detached {
                try AVAudioSession.sharedInstance().setActive(true)
            }.value
        }
    }

    private func deactivateAudioSession() {
        Task.detached {
            do {
                if #available(iOS 27.0, *) {
                    try await AVAudioSession.sharedInstance().deactivate(options: [.notifyOthersOnDeactivation])
                } else {
                    try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
                }
            } catch {
                AppLogger.debug("Audio session deactivation info: \(error.localizedDescription)", tag: "Player")
            }
        }
    }

    deinit {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                cleanup()
            }
        }
    }
}
