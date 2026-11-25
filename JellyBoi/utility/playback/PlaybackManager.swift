//
//  PlaybackManager.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 11/22/26.
//

import Foundation
import SwiftUI
import AVFoundation
import AVKit
import CoreMedia
import JellyfinAPI
import LoggingKit
import SDWebImage

// MARK: - PlaybackURL Helpers

nonisolated enum PlaybackURL {

    /// Turns a stream path into an absolute URL on `client`'s server.
    static func resolved(_ path: String, client: JellyfinClient) -> URL? {
        if let url = URL(string: path), url.scheme != nil {
            return url
        }
        let relative = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return URL(string: relative, relativeTo: client.configuration.url)?.absoluteURL
    }

    /// Forces the bitrate cap on `url` to `maxBitrate`, or returns `url` untouched when no cap was requested.
    static func applyingBitrateCap(_ maxBitrate: Int?, to url: String) -> String {
        guard let maxBitrate, var components = URLComponents(string: url) else { return url }

        let existing = components.queryItems ?? []
        var items = existing.filter { !isBitrateKey($0.name) }
        items.append(URLQueryItem(name: "VideoBitRate", value: String(maxBitrate)))
        items.append(URLQueryItem(name: "MaxStreamingBitrate", value: String(maxBitrate)))
        components.queryItems = items

        return components.string ?? url
    }

    /// Returns `url` with this client's access token as `api_key`, replacing any token already there.
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

    private static func isBitrateKey(_ name: String) -> Bool {
        let key = name.lowercased()
        return key == "videobitrate" || key == "maxstreamingbitrate"
    }
}

// MARK: - PlaybackErrorInfo

struct PlaybackErrorInfo: Identifiable, Sendable {
    let id = UUID()
    var title: String
    var message: String
    var retryAction: (@Sendable () -> Void)?

    init(title: String = "Playback Error", message: String, retryAction: (@Sendable () -> Void)? = nil) {
        self.title = title
        self.message = message
        self.retryAction = retryAction
    }
}

// MARK: - PlayerViewModel

@MainActor
@Observable
final class PlayerViewModel: Identifiable {
    struct UpNextState: Sendable {
        var isVisible: Bool = false
        var secondsRemaining: Int = 30
        var progressFraction: Double = 0.0

        init(isVisible: Bool = false, secondsRemaining: Int = 30, progressFraction: Double = 0.0) {
            self.isVisible = isVisible
            self.secondsRemaining = secondsRemaining
            self.progressFraction = progressFraction
        }
    }

    let id = UUID()
    var player: AVPlayer?
    var itemID: String
    var playbackInfo: PlaybackInfoDto
    var areControlsVisible: Bool = true
    var playbackDiagnosticSummary: String = ""
    var upNextState: UpNextState = UpNextState()
    var nextItem: BaseItemDto? = nil
    var queue: [String] = []
    var legibleGroup: AVMediaSelectionGroup? = nil
    var availableLegibleOptions: [AVMediaSelectionOption] = []
    var isSubtitlesOn: Bool = false
    let playbackRequestedAt: Date
    let preparationDuration: TimeInterval?
    let apiDuration: TimeInterval?
    let isTranscode: Bool
    let playSessionID: String?
    let playMethod: String
    let container: String

    var currentItem: BaseItemDto? {
        LibraryViewModel.shared[itemID]
    }

    private var timeObserverToken: Any? = nil
    private var endObserverToken: NSObjectProtocol? = nil
    private var timeJumpedObserverToken: NSObjectProtocol? = nil
    private var muteObserver: NSKeyValueObservation? = nil
    private var itemStatusObserver: NSKeyValueObservation? = nil
    private var timeControlStatusObserver: NSKeyValueObservation? = nil
    private var isDismissed: Bool = false
    private var isCleanedUp: Bool = false
    private(set) var firstFrameRendered: Bool = false
    private var isReadyToPlayLogged: Bool = false
    private var ttfWaitingTimerTask: Task<Void, Never>? = nil
    private(set) var readyToPlayAt: Date? = nil
    private(set) var firstFrameRenderedAt: Date? = nil
    private var lastLoggedBufferSecond: Int = -1
    let reporter: PlaybackReporter

    init(
        itemID: String,
        playbackInfo: PlaybackInfoDto,
        player: AVPlayer? = nil,
        queue: [String] = [],
        playbackRequestedAt: Date = Date(),
        preparationDuration: TimeInterval? = nil,
        apiDuration: TimeInterval? = nil,
        isTranscode: Bool = false,
        playSessionID: String? = nil,
        playMethod: String = "",
        container: String = "",
        client: JellyfinClient? = nil,
        userID: String? = nil,
        resolvedPlayMethod: PlayMethod = .directStream,
        resolvedMediaSourceID: String? = nil,
        initialPositionTicks: Int = 0,
        initialDurationTicks: Int = 0,
        isEpisode: Bool = false
    ) {
        self.itemID = itemID
        self.playbackInfo = playbackInfo
        self.player = player
        self.queue = queue
        self.playbackRequestedAt = playbackRequestedAt
        self.preparationDuration = preparationDuration
        self.apiDuration = apiDuration
        self.isTranscode = isTranscode
        self.playSessionID = playSessionID
        self.playMethod = playMethod
        self.container = container
        self.reporter = PlaybackReporter(
            client: client,
            userID: userID,
            itemID: itemID,
            mediaSourceID: resolvedMediaSourceID ?? playbackInfo.mediaSourceID,
            playSessionID: playSessionID,
            playMethod: resolvedPlayMethod,
            initialPositionTicks: initialPositionTicks,
            initialDurationTicks: initialDurationTicks,
            audioStreamIndex: playbackInfo.audioStreamIndex,
            subtitleStreamIndex: playbackInfo.subtitleStreamIndex,
            queue: queue,
            isEpisode: isEpisode
        )
        AppLogger.debug("PlayerViewModel initialized for itemID: '\(itemID)', queue count: \(queue.count)")
        resolveNextItem()
        setupPlayerObservations()
        startTTFWaitingTimer()
    }

    private func startTTFWaitingTimer() {
        ttfWaitingTimerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard let self, !self.firstFrameRendered else { break }
                let elapsed = String(format: "%.1f", Date().timeIntervalSince(self.playbackRequestedAt))
                AppLogger.info("Playback TTF timer: waiting for first frame (\(elapsed)s elapsed) for item '\(self.itemID)'")
            }
        }
    }

    func resolveNextItem() {
        guard !queue.isEmpty, let currentIndex = queue.firstIndex(of: itemID), currentIndex + 1 < queue.count else {
            self.nextItem = nil
            AppLogger.debug("No next item in queue for itemID: '\(itemID)'")
            return
        }
        let nextID = queue[currentIndex + 1]
        self.nextItem = LibraryViewModel.shared[nextID]
        AppLogger.debug("Resolved next item in queue: '\(self.nextItem?.name ?? nextID)' (\(nextID))")
    }

    func setupPlayerObservations() {
        guard let player else { return }

        // Periodic time observer to monitor remaining duration and trigger UpNextOverlay
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self, let currentItem = self.player?.currentItem else { return }
                let durationSeconds = currentItem.duration.seconds
                guard durationSeconds.isFinite, durationSeconds > 0 else { return }

                let currentSeconds = time.seconds
                let remaining = durationSeconds - currentSeconds
                let isPaused = self.player?.timeControlStatus == .paused

                self.reporter.handlePeriodicTick(
                    currentSeconds: currentSeconds,
                    durationSeconds: durationSeconds,
                    isPaused: isPaused
                )

                if !self.firstFrameRendered && currentSeconds > 0.05 {
                    self.markFirstFrameRendered()
                }

                let sec = Int(currentSeconds)
                if sec > 0 && sec % 2 == 0 && sec != self.lastLoggedBufferSecond {
                    self.lastLoggedBufferSecond = sec
                    var forwardBuffer: Double = 0.0
                    if let timeRange = currentItem.loadedTimeRanges.first?.timeRangeValue {
                        let bufferStart = CMTimeGetSeconds(timeRange.start)
                        let bufferDuration = CMTimeGetSeconds(timeRange.duration)
                        forwardBuffer = max(0, (bufferStart + bufferDuration) - currentSeconds)
                    }
                    let mem = SystemMetrics.residentMemoryMB
                    AppLogger.info("[BENCHMARK:BUFFER] engine=newBackend item_id=\(self.itemID) playback_sec=\(String(format: "%.1f", currentSeconds)) forward_buffer_sec=\(String(format: "%.2f", forwardBuffer)) preferred_buffer_sec=\(currentItem.preferredForwardBufferDuration) memory_mb=\(String(format: "%.1f", mem))")
                }

                if remaining <= 30 && remaining > 0 && self.nextItem != nil && !self.isDismissed {
                    let secondsRemaining = Int(ceil(remaining))
                    let fraction = max(0, min(1, (30.0 - remaining) / 30.0))
                    withAnimation(.easeInOut(duration: 0.25)) {
                        self.upNextState = UpNextState(
                            isVisible: true,
                            secondsRemaining: secondsRemaining,
                            progressFraction: fraction
                        )
                    }
                } else if remaining <= 0 || remaining > 30 || self.isDismissed {
                    if self.upNextState.isVisible {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            self.upNextState.isVisible = false
                        }
                    }
                }
            }
        }

        // Un-mute observer to prevent silent switch / route change mute bugs
        var lastNonZeroVolume: Float = 1.0
        muteObserver = player.observe(\.isMuted, options: [.new]) { player, _ in
            if player.isMuted {
                if player.volume > 0.0 {
                    lastNonZeroVolume = player.volume
                }
                player.isMuted = false
                player.volume = lastNonZeroVolume > 0.0 ? lastNonZeroVolume : 1.0
            }
        }

        // When item finishes playing to the end, mark completed and automatically advance to next item
        endObserverToken = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let self,
                      let endedItem = notification.object as? AVPlayerItem,
                      endedItem === self.player?.currentItem else { return }
                self.reporter.handleNaturalCompletion()
                Task { @MainActor [weak self] in
                    await self?.playNextItem()
                }
            }
        }

        // Report debounced seek positions when the user scrubs
        timeJumpedObserverToken = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.timeJumpedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let self,
                      let jumpedItem = notification.object as? AVPlayerItem,
                      jumpedItem === self.player?.currentItem else { return }
                let positionSeconds = jumpedItem.currentTime().seconds
                let durationSeconds = jumpedItem.duration.seconds
                let isPaused = self.player?.timeControlStatus == .paused
                self.reporter.handleUserSeek(
                    positionSeconds: positionSeconds,
                    durationSeconds: durationSeconds,
                    isPaused: isPaused
                )
            }
        }

        // Observe currentItem status to populate available subtitle tracks once ready
        if let currentItem = player.currentItem {
            itemStatusObserver = currentItem.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
                if item.status == .failed {
                    AppLogger.error("Player item failed with error: \(item.error?.localizedDescription ?? "unknown error")")
                }
                guard item.status == .readyToPlay else { return }
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if !self.isReadyToPlayLogged {
                        self.isReadyToPlayLogged = true
                        self.readyToPlayAt = Date()
                        let readyElapsed = Date().timeIntervalSince(self.playbackRequestedAt)
                        let readyMs = Int(readyElapsed * 1000)
                        let mem = SystemMetrics.residentMemoryMB
                        AppLogger.info("[BENCHMARK:READINESS] engine=newBackend item_id=\(self.itemID) ready_to_play_ms=\(readyMs) memory_mb=\(String(format: "%.1f", mem))")
                        AppLogger.info("Player item readyToPlay in \(String(format: "%.2f", readyElapsed))s for item '\(self.itemID)'")
                    }
                    await self.loadLegibleOptions()
                }
            }
        }

        // Report playback start/pause/resume transitions and fallback for audio-only items
        timeControlStatusObserver = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            let status = player.timeControlStatus
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch status {
                case .playing:
                    if self.reporter.state == .notReported {
                        self.reporter.handlePlaybackStarted(isPaused: false)
                    } else {
                        self.reporter.handlePauseStateChanged(isPaused: false)
                    }
                    if !self.firstFrameRendered {
                        let hasVideo = self.player?.currentItem?.tracks.contains(where: { $0.assetTrack?.mediaType == .video }) ?? true
                        if !hasVideo {
                            self.markFirstFrameRendered()
                        }
                    }
                case .paused:
                    self.reporter.handlePauseStateChanged(isPaused: true)
                case .waitingToPlayAtSpecifiedRate:
                    // Buffering/stalling is not a user pause.
                    break
                @unknown default:
                    break
                }
            }
        }
    }

    func loadLegibleOptions() async {
        guard let item = player?.currentItem else {
            self.legibleGroup = nil
            self.availableLegibleOptions = []
            self.isSubtitlesOn = false
            return
        }
        do {
            let group = try await item.asset.loadMediaSelectionGroup(for: .legible)
            self.legibleGroup = group
            self.availableLegibleOptions = group?.options ?? []
            if let group {
                let selected = item.currentMediaSelection.selectedMediaOption(in: group)
                self.isSubtitlesOn = (selected != nil)
            } else {
                self.isSubtitlesOn = false
            }
        } catch {
            self.legibleGroup = nil
            self.availableLegibleOptions = []
            self.isSubtitlesOn = false
        }
    }

    func selectSubtitleOption(_ option: AVMediaSelectionOption?) {
        guard let item = player?.currentItem, let group = legibleGroup else { return }
        item.select(option, in: group)
        self.isSubtitlesOn = (option != nil)
    }

    func playNextItem() async {
        guard !queue.isEmpty, let currentIndex = queue.firstIndex(of: itemID), currentIndex + 1 < queue.count else {
            AppLogger.warning("playNextItem called but queue has no subsequent item for itemID: '\(itemID)'")
            return
        }
        let nextID = queue[currentIndex + 1]
        AppLogger.info("Advancing playback to next queued item: '\(nextID)'")
        PlaybackManager.shared.play(
            itemID: nextID,
            playbackInfo: PlaybackInfoDto(),
            fromBeginning: true,
            queue: queue
        )
    }

    func dismissUpNextOverlay() {
        AppLogger.debug("Dismissed up-next overlay for itemID: '\(itemID)'")
        isDismissed = true
        withAnimation(.easeInOut(duration: 0.25)) {
            upNextState.isVisible = false
        }
    }

    func startPlaybackIfNeeded() async {
        AppLogger.debug("startPlaybackIfNeeded invoked for itemID: '\(itemID)'")
        await AVAudioSession.sharedInstance().activateAsynchronously()
        player?.play()
    }

    func markFirstFrameRendered() {
        guard !firstFrameRendered else { return }
        firstFrameRendered = true
        ttfWaitingTimerTask?.cancel()
        ttfWaitingTimerTask = nil

        let firstFrameAt = Date()
        self.firstFrameRenderedAt = firstFrameAt
        let ttfSeconds = firstFrameAt.timeIntervalSince(playbackRequestedAt)
        let ttfFormatted = String(format: "%.2f", ttfSeconds)
        let ttffMs = Int(ttfSeconds * 1000)

        let apiMs = Int((apiDuration ?? 0) * 1000)
        let prepMs = Int((preparationDuration ?? 0) * 1000)
        let decodeMs = readyToPlayAt != nil ? Int(firstFrameAt.timeIntervalSince(readyToPlayAt!) * 1000) : max(0, ttffMs - prepMs)

        AppLogger.info("[BENCHMARK:RENDER] engine=newBackend item_id=\(itemID) first_frame_rendered_ms=\(ttffMs) decode_ms=\(decodeMs)")
        AppLogger.info("[BENCHMARK:BREAKDOWN] engine=newBackend item_id=\(itemID) ttff_ms=\(ttffMs) t_api_ms=\(apiMs) t_transcode_ms=\(isTranscode ? apiMs : 0) t_seg0_ms=\(prepMs) t_decode_ms=\(decodeMs)")

        if let prep = preparationDuration {
            let prepFormatted = String(format: "%.2f", prep)
            let renderFormatted = String(format: "%.2f", max(0, ttfSeconds - prep))
            AppLogger.success("Playback TTF (time to first frame): \(ttfFormatted)s (preparation: \(prepFormatted)s, render: \(renderFormatted)s) for item '\(itemID)'")
        } else {
            AppLogger.success("Playback TTF (time to first frame): \(ttfFormatted)s for item '\(itemID)'")
        }

        #if DEBUG
        if !playbackDiagnosticSummary.isEmpty && !playbackDiagnosticSummary.contains("TTF") {
            playbackDiagnosticSummary += " • TTF: \(ttfFormatted)s"
        }
        #endif
    }

    func cleanup() {
        guard !isCleanedUp else { return }
        isCleanedUp = true
        AppLogger.info("Cleaning up PlayerViewModel for itemID: '\(itemID)'")
        ttfWaitingTimerTask?.cancel()
        ttfWaitingTimerTask = nil
        if !firstFrameRendered {
            let elapsed = String(format: "%.2f", Date().timeIntervalSince(playbackRequestedAt))
            AppLogger.info("Playback TTF timer stopped after \(elapsed)s before first frame rendered for item '\(itemID)'")
        }

        reporter.stop()

        if let currentItem = player?.currentItem, let log = currentItem.accessLog(), let lastEvent = log.events.last {
            let startupTime = lastEvent.startupTime
            let indicated = Int(lastEvent.indicatedBitrate / 1000)
            let observed = Int(lastEvent.observedBitrate / 1000)
            let stalls = lastEvent.numberOfStalls
            let watched = lastEvent.durationWatched
            AppLogger.info("[BENCHMARK:ACCESS_LOG] engine=newBackend item_id=\(self.itemID) startup_time_s=\(String(format: "%.3f", startupTime)) indicated_kbps=\(indicated) observed_kbps=\(observed) stalls=\(stalls) duration_watched_s=\(String(format: "%.1f", watched))")
        }

        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
            timeObserverToken = nil
        }
        if let endToken = endObserverToken {
            NotificationCenter.default.removeObserver(endToken)
            endObserverToken = nil
        }
        if let jumpToken = timeJumpedObserverToken {
            NotificationCenter.default.removeObserver(jumpToken)
            timeJumpedObserverToken = nil
        }
        muteObserver?.invalidate()
        muteObserver = nil
        itemStatusObserver?.invalidate()
        itemStatusObserver = nil
        timeControlStatusObserver?.invalidate()
        timeControlStatusObserver = nil

        Task {
            await AVAudioSession.sharedInstance().deactivateAsynchronously()
        }

        player?.pause()
        player = nil
    }
}

// MARK: - PlaybackManager

@MainActor
@Observable
final class PlaybackManager {
    static let shared = PlaybackManager()

    // MARK: - State

    var isPreparing: Bool = false
    var loadingMessage: String = "Preparing Playback..."
    var currentError: PlaybackErrorInfo? = nil
    var activePlayerViewModel: PlayerViewModel? = nil

    weak var client: JellyfinClient?
    var userID: String?

    private var preparationTask: Task<Void, Never>?

    init() {
        AppLogger.debug("PlaybackManager singleton initialized")
    }

    // MARK: - Stream URL Construction

    /// Builds a direct static stream URL for an item.
    /// Returns the local file URL if the media is downloaded locally, or the direct static Jellyfin stream URL.
    public func directPlayURL(itemID: String, container: String? = nil, mediaSourceID: String? = nil) -> URL? {
        if let localURL = DownloadManager.shared.localFileURL(for: itemID) {
            AppLogger.debug("directPlayURL resolved to local file for item '\(itemID)': \(localURL.path)")
            return localURL
        }

        guard let client else {
            AppLogger.warning("Cannot construct directPlayURL for item '\(itemID)': Jellyfin client is nil")
            return nil
        }

        guard var components = URLComponents(url: client.configuration.url, resolvingAgainstBaseURL: false) else {
            AppLogger.error("Failed to construct URL components from client URL: \(client.configuration.url)")
            return nil
        }

        var path = components.path
        if !path.hasSuffix("/") { path += "/" }
        if let container, !container.isEmpty {
            path += "Videos/\(itemID)/stream.\(container)"
        } else {
            path += "Videos/\(itemID)/stream"
        }
        components.path = path

        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "static", value: "true")
        ]

        if let sourceID = mediaSourceID {
            queryItems.append(URLQueryItem(name: "MediaSourceId", value: sourceID))
        }

        if !client.configuration.deviceID.isEmpty {
            queryItems.append(URLQueryItem(name: "DeviceId", value: client.configuration.deviceID))
        }

        if let token = client.configuration.accessToken, !token.isEmpty {
            queryItems.append(URLQueryItem(name: "api_key", value: token))
        }

        components.queryItems = queryItems
        let result = components.url
        AppLogger.debug("Constructed direct play URL: \(result?.absoluteString ?? "nil")")
        return result
    }

    /// Builds a transcoding / remuxing (non-direct play HLS) URL for an item.
    public func transcodingURL(
        itemID: String,
        playbackInfo: PlaybackInfoDto = PlaybackInfoDto(),
        startTimeTicks: Int? = nil,
        playSessionID: String? = nil
    ) -> URL? {
        guard let client else {
            AppLogger.warning("Cannot construct transcodingURL for item '\(itemID)': Jellyfin client is nil")
            return nil
        }

        let sourceID = playbackInfo.mediaSourceID ?? itemID
        let playSessionID = playSessionID ?? UUID().uuidString

        guard var components = URLComponents(url: client.configuration.url, resolvingAgainstBaseURL: false) else {
            AppLogger.error("Failed to construct URL components for transcoding URL from client URL: \(client.configuration.url)")
            return nil
        }

        var path = components.path
        if !path.hasSuffix("/") { path += "/" }
        path += "Videos/\(itemID)/master.m3u8"
        components.path = path

        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "MediaSourceId", value: sourceID),
            URLQueryItem(name: "PlaySessionId", value: playSessionID),
            URLQueryItem(name: "VideoCodec", value: "h264,hevc"),
            URLQueryItem(name: "AudioCodec", value: "aac,mp3,ac3,eac3"),
            URLQueryItem(name: "TranscodingMaxAudioChannels", value: "6"),
            URLQueryItem(name: "SegmentContainer", value: "mp4"),
            URLQueryItem(name: "MinSegments", value: "1"),
            URLQueryItem(name: "BreakOnNonKeyFrames", value: "True")
        ]

        if !client.configuration.deviceID.isEmpty {
            queryItems.append(URLQueryItem(name: "DeviceId", value: client.configuration.deviceID))
        }

        if let ticks = startTimeTicks ?? playbackInfo.startTimeTicks, ticks > 0 {
            queryItems.append(URLQueryItem(name: "StartTimeTicks", value: String(ticks)))
        }

        if let audioIndex = playbackInfo.audioStreamIndex {
            queryItems.append(URLQueryItem(name: "AudioStreamIndex", value: String(audioIndex)))
        }

        if let subtitleIndex = playbackInfo.subtitleStreamIndex, subtitleIndex >= 0 {
            queryItems.append(URLQueryItem(name: "SubtitleStreamIndex", value: String(subtitleIndex)))
        }

        if let maxBitrate = playbackInfo.maxStreamingBitrate, maxBitrate > 0 {
            queryItems.append(URLQueryItem(name: "VideoBitRate", value: String(maxBitrate)))
            queryItems.append(URLQueryItem(name: "MaxStreamingBitrate", value: String(maxBitrate)))
        }

        if let token = client.configuration.accessToken, !token.isEmpty {
            queryItems.append(URLQueryItem(name: "api_key", value: token))
        }

        components.queryItems = queryItems
        let result = components.url
        AppLogger.debug("Constructed transcoding URL: \(result?.absoluteString ?? "nil") (sourceID: \(sourceID), sessionID: \(playSessionID))")
        return result
    }

    /// Resolves the stream URL (direct play vs non-direct play/transcoding) based on options and local media availability.
    public func streamURL(
        itemID: String,
        playbackInfo: PlaybackInfoDto = PlaybackInfoDto(),
        startTimeTicks: Int? = nil,
        playSessionID: String? = nil
    ) -> URL? {
        // If downloaded locally, always use the local file URL (direct play)
        if let localURL = DownloadManager.shared.localFileURL(for: itemID) {
            AppLogger.debug("streamURL resolved to local file for item '\(itemID)': \(localURL.path)")
            return localURL
        }

        // Check if transcoding is explicitly requested or required (bitrate cap, non-compatible subtitle, or disabled direct play)
        let hasBitrateCap = (playbackInfo.maxStreamingBitrate != nil && playbackInfo.maxStreamingBitrate! > 0)
        let item = LibraryViewModel.shared[itemID]
        let selectedSubtitleStream = item?.mediaStreams?.first(where: { $0.type == .subtitle && $0.index == playbackInfo.subtitleStreamIndex })
        let requiresSubtitleTranscode = (selectedSubtitleStream != nil && !ApplePlayableSubtitle.isCompatible(selectedSubtitleStream))
        let forcesTranscoding = playbackInfo.enableTranscoding == true && playbackInfo.enableDirectPlay == false

        if hasBitrateCap || requiresSubtitleTranscode || forcesTranscoding {
            AppLogger.debug("streamURL resolving via transcoding URL for item '\(itemID)' (bitrateCap: \(hasBitrateCap), nonCompatibleSubtitle: \(requiresSubtitleTranscode), forcesTranscoding: \(forcesTranscoding))")
            return transcodingURL(itemID: itemID, playbackInfo: playbackInfo, startTimeTicks: startTimeTicks, playSessionID: playSessionID)
        } else {
            AppLogger.debug("streamURL resolving via direct play with transcoding fallback for item '\(itemID)'")
            let directContainer = ApplePlayableContainer.preferredContainer(for: item?.container)
            return directPlayURL(itemID: itemID, container: directContainer, mediaSourceID: playbackInfo.mediaSourceID)
                ?? transcodingURL(itemID: itemID, playbackInfo: playbackInfo, startTimeTicks: startTimeTicks, playSessionID: playSessionID)
        }
    }

    // MARK: - Playback Engine Lifecycle

    private func playNextInQueue() {
        Task(priority: .userInitiated) { @MainActor [weak self] in
            await self?.activePlayerViewModel?.playNextItem()
        }
    }

    /// Plays the requested item by presenting the player UI on demand.
    func play(
        itemID: String,
        playbackInfo: PlaybackInfoDto = PlaybackInfoDto(),
        fromBeginning: Bool = false,
        queue: [String]? = nil
    ) {
        let preparationStartedAt = Date()
        AppLogger.info("Play invoked for itemID: '\(itemID)', fromBeginning: \(fromBeginning), queue count: \(queue?.count ?? 0) (Playback TTF timer started)")

        // Cancel any pending preparation task and teardown existing player
        preparationTask?.cancel()
        preparationTask = nil
        activePlayerViewModel?.cleanup()
        activePlayerViewModel = nil

        let resumeTicks: Int? = fromBeginning ? 0 : {
            let item = LibraryViewModel.shared[itemID]
            let ticks = item?.resumePlaybackTicks ?? 0
            return ticks > 0 ? ticks : nil
        }()

        if let resumeTicks, resumeTicks > 0 {
            let seconds = Double(resumeTicks) / 10_000_000.0
            AppLogger.info("Resuming item '\(itemID)' at \(String(format: "%.2f", seconds))s (\(resumeTicks) ticks)")
        } else {
            AppLogger.info("Starting item '\(itemID)' from beginning")
        }

        // 1. Instant check for local download (offline direct play)
        if let localURL = DownloadManager.shared.localFileURL(for: itemID) {
            AppLogger.info("Item '\(itemID)' is available locally at '\(localURL.path)'. Initiating local playback.")
            isPreparing = false

            Task {
                await AVAudioSession.sharedInstance().activateAsynchronously()
            }

            let playerItem = AVPlayerItem(url: localURL)
            var fallbackItem = BaseItemDto()
            fallbackItem.id = itemID
            let item = LibraryViewModel.shared[itemID] ?? fallbackItem
            playerItem.configureMetadata(for: item, client: client)

            Task { [weak playerItem] in
                await playerItem?.selectRequestedSubtitle(
                    index: playbackInfo.subtitleStreamIndex,
                    streams: item.mediaStreams
                )
            }

            let player = AVPlayer(playerItem: playerItem)
            player.allowsExternalPlayback = true
            player.usesExternalPlaybackWhileExternalScreenIsActive = true
            player.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible
            player.preventsDisplaySleepDuringVideoPlayback = true

            if let resumeTicks, resumeTicks > 0 {
                let seconds = Double(resumeTicks) / 10_000_000.0
                let time = CMTime(seconds: seconds, preferredTimescale: 600)
                AppLogger.debug("Seeking AVPlayer to \(String(format: "%.2f", seconds))s for local playback")
                player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero, completionHandler: { _ in })
            }

            let prepElapsed = Date().timeIntervalSince(preparationStartedAt)
            let elapsed = String(format: "%.2f", prepElapsed)
            AppLogger.success("Offline playback started successfully in \(elapsed)s for item '\(itemID)'")

            let effectiveUserID = playbackInfo.userID ?? self.userID
            let vm = PlayerViewModel(
                itemID: itemID,
                playbackInfo: playbackInfo,
                player: player,
                queue: queue ?? [],
                playbackRequestedAt: preparationStartedAt,
                preparationDuration: prepElapsed,
                apiDuration: 0,
                isTranscode: false,
                playSessionID: nil,
                playMethod: "Direct Play (Local)",
                container: localURL.pathExtension.uppercased(),
                client: self.client,
                userID: effectiveUserID,
                resolvedPlayMethod: .directPlay,
                resolvedMediaSourceID: playbackInfo.mediaSourceID,
                initialPositionTicks: resumeTicks ?? 0,
                initialDurationTicks: item.runTimeTicks.map { Int($0) } ?? 0,
                isEpisode: item.type == .episode
            )
            vm.playbackDiagnosticSummary = "Direct Play (Local) • \(localURL.pathExtension.uppercased())"
            self.activePlayerViewModel = vm
            player.play()
            return
        }

        // 2. Prepare remote playback asynchronously with Jellyfin server negotiation
        isPreparing = true
        loadingMessage = "Preparing Playback..."

        let task = Task<Void, Never> { @MainActor [weak self] in
            guard let self else { return }

            guard let client = self.client else {
                AppLogger.error("Cannot start playback for item '\(itemID)': Jellyfin client is nil")
                self.isPreparing = false
                self.currentError = PlaybackErrorInfo(
                    title: "Playback Error",
                    message: "No server connection available for playback."
                )
                return
            }

            let effectiveUserID = playbackInfo.userID ?? self.userID

            // Negotiate stream delivery with Jellyfin API using Apple Native Device Profile
            AppLogger.info("Negotiating stream resolution with Jellyfin server using Apple Native Device Profile (POST /Items/\(itemID)/PlaybackInfo)")
            let negotiationStartedAt = Date()

            var negotiatedURL: URL?
            var playSessionID: String?
            var diagnosticSummary: String = ""
            var resolvedContainer: String = "unknown"
            var resolvedPlayMethod: PlayMethod = .directStream
            var resolvedMediaSourceID: String? = playbackInfo.mediaSourceID

            // Build full PlaybackInfoDto with device profile
            var requestDto = playbackInfo
            requestDto.deviceProfile = JellyfinDeviceProfile.appleNative
            requestDto.userID = effectiveUserID
            requestDto.startTimeTicks = resumeTicks
            requestDto.allowAudioStreamCopy = true
            requestDto.allowVideoStreamCopy = (playbackInfo.maxStreamingBitrate == nil)
            requestDto.enableDirectPlay = playbackInfo.enableDirectPlay ?? (playbackInfo.maxStreamingBitrate == nil)
            requestDto.enableDirectStream = playbackInfo.enableDirectStream ?? (playbackInfo.maxStreamingBitrate == nil)
            requestDto.enableTranscoding = playbackInfo.enableTranscoding ?? true

            let queryParams = Paths.GetPostedPlaybackInfoParameters(
                userID: effectiveUserID,
                maxStreamingBitrate: playbackInfo.maxStreamingBitrate,
                startTimeTicks: resumeTicks,
                audioStreamIndex: playbackInfo.audioStreamIndex,
                subtitleStreamIndex: playbackInfo.subtitleStreamIndex,
                mediaSourceID: playbackInfo.mediaSourceID,
                enableDirectPlay: requestDto.enableDirectPlay,
                enableDirectStream: requestDto.enableDirectStream,
                enableTranscoding: requestDto.enableTranscoding,
                allowVideoStreamCopy: requestDto.allowVideoStreamCopy,
                allowAudioStreamCopy: requestDto.allowAudioStreamCopy
            )

            do {
                let response = try await client.fetchPostedPlaybackInfo(
                    itemID: itemID,
                    playbackDto: requestDto,
                    parameters: queryParams
                )

                guard !Task.isCancelled else {
                    AppLogger.info("Playback preparation cancelled after receiving server PlaybackInfo")
                    self.isPreparing = false
                    return
                }

                let negotiationElapsed = String(format: "%.2f", Date().timeIntervalSince(negotiationStartedAt))
                playSessionID = response.playSessionID
                let sources = response.mediaSources ?? []
                AppLogger.info("Server PlaybackInfo response received in \(negotiationElapsed)s: playSessionID=\(playSessionID ?? "nil"), mediaSources=\(sources.count)")

                let selectedSource = sources.first(where: { $0.id == playbackInfo.mediaSourceID }) ?? sources.first
                if let source = selectedSource {
                    resolvedMediaSourceID = source.id ?? playbackInfo.mediaSourceID
                    let container = source.container?.lowercased() ?? "unknown"
                    let directContainer = ApplePlayableContainer.preferredContainer(for: container)
                    resolvedContainer = directContainer ?? container
                    let isAppleNative = directContainer != nil
                    let directPlayAllowed = source.isSupportsDirectPlay == true && isAppleNative && (playbackInfo.maxStreamingBitrate == nil)

                    if let transURL = source.transcodingURL, !transURL.isEmpty {
                        // Server decided transcoding/remuxing is required
                        let cappedURL = PlaybackURL.applyingBitrateCap(playbackInfo.maxStreamingBitrate, to: transURL)
                        if let resolved = PlaybackURL.resolved(cappedURL, client: client) {
                            let authenticated = PlaybackURL.applyingAuthentication(resolved, token: client.configuration.accessToken)
                            negotiatedURL = authenticated
                            let isTranscoding = (playbackInfo.maxStreamingBitrate != nil) || (source.isSupportsDirectStream != true)
                            resolvedPlayMethod = isTranscoding ? .transcode : .directStream
                            let method = isTranscoding ? "Transcode" : "Direct Stream"
                            diagnosticSummary = "\(method) • \(container) • \(source.bitrate.map { "\($0 / 1000) kbps" } ?? "Auto")"
                            AppLogger.info("Using server-provided transcoding URL (\(method)): \(authenticated.absoluteString)")
                        }
                    } else if directPlayAllowed, let directContainer {
                        // Direct Play
                        if let directURL = client.directVideoStreamURL(itemID: itemID, container: directContainer, sessionID: playSessionID, mediaSourceID: source.id) {
                            let authenticated = PlaybackURL.applyingAuthentication(directURL, token: client.configuration.accessToken)
                            negotiatedURL = authenticated
                            resolvedPlayMethod = .directPlay
                            diagnosticSummary = "Direct Play • \(directContainer.uppercased())"
                            AppLogger.info("Direct play authorized by server for container '\(directContainer)': \(authenticated.absoluteString)")
                        }
                    } else {
                        // Container requires remuxing or custom stream selection
                        AppLogger.info("Container '\(container)' or options require HLS delivery; requesting client-constructed transcoding URL")
                        let effectiveSessionID = playSessionID ?? UUID().uuidString
                        playSessionID = effectiveSessionID
                        if let hlsURL = self.transcodingURL(
                            itemID: itemID,
                            playbackInfo: playbackInfo,
                            startTimeTicks: resumeTicks,
                            playSessionID: effectiveSessionID
                        ) {
                            negotiatedURL = hlsURL
                            let hasBitrateCap = (playbackInfo.maxStreamingBitrate ?? 0) > 0
                            let item = LibraryViewModel.shared[itemID]
                            let selectedSubtitleStream = item?.mediaStreams?.first(where: { $0.type == .subtitle && $0.index == playbackInfo.subtitleStreamIndex })
                            let requiresSubtitleTranscode = (selectedSubtitleStream != nil && !ApplePlayableSubtitle.isCompatible(selectedSubtitleStream))
                            resolvedPlayMethod = (hasBitrateCap || requiresSubtitleTranscode) ? .transcode : .directStream
                            let method = resolvedPlayMethod == .transcode ? "Transcode" : "Direct Stream"
                            diagnosticSummary = "\(method) • \(container)"
                            AppLogger.info("Generated client HLS transcoding URL: \(hlsURL.absoluteString)")
                        }
                    }
                } else {
                    AppLogger.warning("No media sources returned by server; falling back to client-constructed stream URL")
                    let effectiveSessionID = playSessionID ?? UUID().uuidString
                    playSessionID = effectiveSessionID
                    let fallbackURL = self.streamURL(
                        itemID: itemID,
                        playbackInfo: playbackInfo,
                        startTimeTicks: resumeTicks,
                        playSessionID: effectiveSessionID
                    )
                    negotiatedURL = fallbackURL
                    resolvedPlayMethod = (fallbackURL?.path.contains("master.m3u8") == true) ? .transcode : .directPlay
                    diagnosticSummary = "Stream"
                }
            } catch is CancellationError {
                AppLogger.info("Playback preparation cancelled during network negotiation for item '\(itemID)'")
                self.isPreparing = false
                return
            } catch {
                if Task.isCancelled {
                    AppLogger.info("Playback preparation task was cancelled")
                    self.isPreparing = false
                    return
                }
                AppLogger.warning("Server PlaybackInfo negotiation failed (\(error.localizedDescription)); attempting client fallback stream URL")
                let effectiveSessionID = playSessionID ?? UUID().uuidString
                playSessionID = effectiveSessionID
                let fallbackURL = self.streamURL(
                    itemID: itemID,
                    playbackInfo: playbackInfo,
                    startTimeTicks: resumeTicks,
                    playSessionID: effectiveSessionID
                )
                negotiatedURL = fallbackURL
                resolvedPlayMethod = (fallbackURL?.path.contains("master.m3u8") == true) ? .transcode : .directPlay
                diagnosticSummary = "Fallback Stream"
            }

            guard !Task.isCancelled else {
                AppLogger.info("Playback preparation task cancelled before player initialization")
                self.isPreparing = false
                return
            }

            guard let url = negotiatedURL else {
                AppLogger.error("Failed to construct or resolve playable stream URL for item '\(itemID)'")
                self.isPreparing = false
                self.currentError = PlaybackErrorInfo(
                    title: "Playback Error",
                    message: "Unable to resolve stream URL from server.",
                    retryAction: { [weak self] in
                        Task { @MainActor [weak self] in
                            self?.play(itemID: itemID, playbackInfo: playbackInfo, fromBeginning: fromBeginning, queue: queue)
                        }
                    }
                )
                return
            }

            AppLogger.info("Initializing AVPlayer with stream URL: \(url.absoluteString)")

            await AVAudioSession.sharedInstance().activateAsynchronously()

            let playerItem: AVPlayerItem
            if url.isFileURL {
                playerItem = AVPlayerItem(url: url)
            } else {
                let asset = JellyfinAuthorization.asset(url: url, client: client)
                playerItem = AVPlayerItem(asset: asset)
            }

            var fallbackItem = BaseItemDto()
            fallbackItem.id = itemID
            let item = LibraryViewModel.shared[itemID] ?? fallbackItem
            playerItem.configureMetadata(for: item, client: client)

            let player = AVPlayer(playerItem: playerItem)
            player.allowsExternalPlayback = true
            player.usesExternalPlaybackWhileExternalScreenIsActive = true
            player.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible
            player.preventsDisplaySleepDuringVideoPlayback = true

            if let resumeTicks, resumeTicks > 0 {
                let seconds = Double(resumeTicks) / 10_000_000.0
                let time = CMTime(seconds: seconds, preferredTimescale: 600)
                AppLogger.debug("Seeking AVPlayer to \(String(format: "%.2f", seconds))s")
                await player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
            }

            let prepElapsed = Date().timeIntervalSince(preparationStartedAt)
            let totalElapsed = String(format: "%.2f", prepElapsed)
            AppLogger.success("Playback preparation reached ready in \(totalElapsed)s for item '\(itemID)'")

            let negotiationElapsed = Date().timeIntervalSince(negotiationStartedAt)
            let isTranscode = diagnosticSummary.contains("Transcode")
            AppLogger.info("[BENCHMARK:API] engine=newBackend item_id=\(itemID) duration_ms=\(Int(negotiationElapsed * 1000)) session_id=\(playSessionID ?? "none") method=\(diagnosticSummary) is_transcode=\(isTranscode) container=\(resolvedContainer)")

            let vm = PlayerViewModel(
                itemID: itemID,
                playbackInfo: playbackInfo,
                player: player,
                queue: queue ?? [],
                playbackRequestedAt: preparationStartedAt,
                preparationDuration: prepElapsed,
                apiDuration: negotiationElapsed,
                isTranscode: isTranscode,
                playSessionID: playSessionID,
                playMethod: diagnosticSummary,
                container: resolvedContainer,
                client: client,
                userID: effectiveUserID,
                resolvedPlayMethod: resolvedPlayMethod,
                resolvedMediaSourceID: resolvedMediaSourceID,
                initialPositionTicks: resumeTicks ?? 0,
                initialDurationTicks: item.runTimeTicks.map { Int($0) } ?? 0,
                isEpisode: item.type == .episode
            )
            vm.playbackDiagnosticSummary = diagnosticSummary
            self.activePlayerViewModel = vm
            self.isPreparing = false
            player.play()
        }

        self.preparationTask = task
    }

    func cancelPreparation() {
        AppLogger.info("Playback preparation cancelled by user")
        preparationTask?.cancel()
        preparationTask = nil
        isPreparing = false
    }

    func stop() {
        AppLogger.info("Stopping playback and releasing player")
        cancelPreparation()
        Task {
            await AVAudioSession.sharedInstance().deactivateAsynchronously()
        }
        activePlayerViewModel?.cleanup()
        activePlayerViewModel = nil
    }

    func clearError() {
        AppLogger.debug("Clearing playback error")
        currentError = nil
    }

    // MARK: - Compatibility Bridges (for existing callers transitioning to itemID)

    func play(
        item: BaseItemDto,
        fromBeginning: Bool = false,
        client: JellyfinClient? = nil,
        userID: String? = nil,
        mediaSourceID: String? = nil,
        audioStreamIndex: Int? = nil,
        subtitleStreamIndex: Int? = nil,
        maxBitrate: Int? = nil,
        queue: [BaseItemDto]? = nil
    ) {
        guard let itemID = item.id else {
            AppLogger.error("Cannot play item without ID: '\(item.name ?? "Unknown")'")
            return
        }
        LibraryViewModel.shared[itemID] = item
        AppLogger.info("Compatibility play invoked for item '\(item.name ?? itemID)' (ID: \(itemID))")
        if let client { self.client = client }
        if let userID { self.userID = userID }

        let info = PlaybackInfoDto(
            audioStreamIndex: audioStreamIndex,
            maxStreamingBitrate: maxBitrate,
            mediaSourceID: mediaSourceID,
            subtitleStreamIndex: subtitleStreamIndex,
            userID: userID ?? self.userID
        )
        play(itemID: itemID, playbackInfo: info, fromBeginning: fromBeginning, queue: queue?.compactMap(\.id))
    }
}

// MARK: - AVPlayerItem System Metadata

extension AVPlayerItem {
    /// Configures system metadata (title, artist, genres, and artwork) on the player item.
    /// Because `AVPlayerViewController.updatesNowPlayingInfoCenter` is enabled, iOS automatically
    /// publishes this metadata to Lock Screen, Dynamic Island, Control Center, and AirPlay.
    func configureMetadata(for item: BaseItemDto, client: JellyfinClient?) {
        var items: [AVMetadataItem] = []

        func makeItem(_ identifier: AVMetadataIdentifier, value: NSString?) -> AVMetadataItem? {
            guard let value, value.length > 0 else { return nil }
            let meta = AVMutableMetadataItem()
            meta.identifier = identifier
            meta.value = value
            meta.extendedLanguageTag = "und"
            return meta
        }

        if let titleItem = makeItem(.commonIdentifierTitle, value: item.playbackTitle as NSString) {
            items.append(titleItem)
        }

        if let subtitle = item.playbackSubtitle {
            if let subtitleItem = makeItem(.commonIdentifierArtist, value: subtitle as NSString) {
                items.append(subtitleItem)
            }
            if let trackSubTitle = makeItem(.iTunesMetadataTrackSubTitle, value: subtitle as NSString) {
                items.append(trackSubTitle)
            }
        }

        if let overview = item.overview,
           let descItem = makeItem(.commonIdentifierDescription, value: overview as NSString) {
            items.append(descItem)
        }

        if let genres = item.genres, !genres.isEmpty,
           let genreItem = makeItem(.quickTimeMetadataGenre, value: genres.joined(separator: ", ") as NSString) {
            items.append(genreItem)
        }

        self.externalMetadata = items

        // Asynchronously load artwork from cache or network and attach to externalMetadata
        let urls = item.artworkURLs(client: client)
        guard !urls.isEmpty else { return }

        Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            for url in urls {
                let artworkData: Data? = await withCheckedContinuation { continuation in
                    SDWebImageManager.shared.loadImage(
                        with: url,
                        options: [.continueInBackground],
                        progress: nil
                    ) { image, data, _, _, _, _ in
                        let resultData = data ?? image?.jpegData(compressionQuality: 0.85)
                        continuation.resume(returning: resultData)
                    }
                }

                if let validData = artworkData, !validData.isEmpty {
                    await MainActor.run {
                        let artworkItem = AVMutableMetadataItem()
                        artworkItem.identifier = .commonIdentifierArtwork
                        artworkItem.dataType = validData.first == 0x89
                            ? (kCMMetadataBaseDataType_PNG as String)
                            : (kCMMetadataBaseDataType_JPEG as String)
                        artworkItem.value = validData as NSData
                        artworkItem.extendedLanguageTag = "und"

                        var current = self.externalMetadata
                        current.removeAll { $0.identifier == .commonIdentifierArtwork }
                        current.append(artworkItem)
                        self.externalMetadata = current
                    }
                    break
                }
            }
        }
    }

    /// Auto-selects the requested subtitle track in the player item's legible media selection group.
    func selectRequestedSubtitle(index: Int?, streams: [MediaStream]?) async {
        guard let group = try? await asset.loadMediaSelectionGroup(for: .legible) else { return }

        if index == -1 {
            select(nil, in: group)
            AppLogger.debug("Deselected subtitle stream group for item (Subtitles Off)")
            return
        }

        if let subIndex = index, subIndex >= 0 {
            if let targetStream = streams?.first(where: { $0.type == .subtitle && $0.index == subIndex }) {
                let streamLang = targetStream.language?.lowercased()
                if let match = group.options.first(where: { opt in
                    if let lang = streamLang, (opt.extendedLanguageTag?.lowercased() == lang || opt.locale?.identifier.lowercased().hasPrefix(lang) == true) {
                        return true
                    }
                    if let title = targetStream.title, opt.displayName.localizedCaseInsensitiveContains(title) {
                        return true
                    }
                    return false
                }) {
                    select(match, in: group)
                    AppLogger.debug("Auto-selected subtitle track: '\(match.displayName)'")
                }
            }
        }
    }
}

// MARK: - AVAudioSession Concurrency Extension

private extension AVAudioSession {
    func activateAsynchronously() async {
        if #available(iOS 27.0, *) {
            _ = try? await activate()
        } else {
            await Task.detached {
                try? self.setActive(true)
            }.value
        }
    }

    func deactivateAsynchronously(options: AVAudioSession.SetActiveOptions = .notifyOthersOnDeactivation) async {
        if #available(iOS 27.0, *) {
            _ = try? await deactivate(options: .notifyOthersOnDeactivation)
        } else {
            await Task.detached {
                try? self.setActive(false, options: options)
            }.value
        }
    }
}
