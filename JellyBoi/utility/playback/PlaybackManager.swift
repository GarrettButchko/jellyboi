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
import JellyfinAPI
import LoggingKit

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

    init(itemID: String, playbackInfo: PlaybackInfoDto, player: AVPlayer? = nil, queue: [String] = []) {
        self.itemID = itemID
        self.playbackInfo = playbackInfo
        self.player = player
        self.queue = queue
        AppLogger.debug("PlayerViewModel initialized for itemID: '\(itemID)', queue count: \(queue.count)")
        resolveNextItem()
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
        upNextState.isVisible = false
    }

    func startPlaybackIfNeeded() async {
        AppLogger.debug("startPlaybackIfNeeded invoked for itemID: '\(itemID)'")
        player?.play()
    }

    func cleanup() {
        AppLogger.info("Cleaning up PlayerViewModel for itemID: '\(itemID)'")
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
    public func directPlayURL(itemID: String, mediaSourceID: String? = nil) -> URL? {
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
        path += "Videos/\(itemID)/stream"
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
        startTimeTicks: Int? = nil
    ) -> URL? {
        guard let client else {
            AppLogger.warning("Cannot construct transcodingURL for item '\(itemID)': Jellyfin client is nil")
            return nil
        }

        let sourceID = playbackInfo.mediaSourceID ?? itemID
        let playSessionID = UUID().uuidString

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
        startTimeTicks: Int? = nil
    ) -> URL? {
        // If downloaded locally, always use the local file URL (direct play)
        if let localURL = DownloadManager.shared.localFileURL(for: itemID) {
            AppLogger.debug("streamURL resolved to local file for item '\(itemID)': \(localURL.path)")
            return localURL
        }

        // Check if transcoding is explicitly requested or required (bitrate cap, subtitle selection, or disabled direct play)
        let hasBitrateCap = (playbackInfo.maxStreamingBitrate != nil && playbackInfo.maxStreamingBitrate! > 0)
        let hasCustomSubtitle = (playbackInfo.subtitleStreamIndex != nil && playbackInfo.subtitleStreamIndex! >= 0)
        let forcesTranscoding = playbackInfo.enableTranscoding == true && playbackInfo.enableDirectPlay == false

        if hasBitrateCap || hasCustomSubtitle || forcesTranscoding {
            AppLogger.debug("streamURL resolving via transcoding URL for item '\(itemID)' (bitrateCap: \(hasBitrateCap), customSubtitle: \(hasCustomSubtitle), forcesTranscoding: \(forcesTranscoding))")
            return transcodingURL(itemID: itemID, playbackInfo: playbackInfo, startTimeTicks: startTimeTicks)
        } else {
            AppLogger.debug("streamURL resolving via direct play with transcoding fallback for item '\(itemID)'")
            return directPlayURL(itemID: itemID, mediaSourceID: playbackInfo.mediaSourceID)
                ?? transcodingURL(itemID: itemID, playbackInfo: playbackInfo, startTimeTicks: startTimeTicks)
        }
    }

    // MARK: - Playback Engine Lifecycle

    /// Plays the requested item by presenting the player UI on demand.
    func play(
        itemID: String,
        playbackInfo: PlaybackInfoDto = PlaybackInfoDto(),
        fromBeginning: Bool = false,
        queue: [String]? = nil
    ) {
        let preparationStartedAt = Date()
        AppLogger.info("Play invoked for itemID: '\(itemID)', fromBeginning: \(fromBeginning), queue count: \(queue?.count ?? 0)")

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

            let playerItem = AVPlayerItem(url: localURL)
            let player = AVPlayer(playerItem: playerItem)

            if let resumeTicks, resumeTicks > 0 {
                let seconds = Double(resumeTicks) / 10_000_000.0
                let time = CMTime(seconds: seconds, preferredTimescale: 600)
                AppLogger.debug("Seeking AVPlayer to \(String(format: "%.2f", seconds))s for local playback")
                player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero, completionHandler: { _ in })
            }

            let vm = PlayerViewModel(itemID: itemID, playbackInfo: playbackInfo, player: player, queue: queue ?? [])
            vm.playbackDiagnosticSummary = "Direct Play (Local) • \(localURL.pathExtension.uppercased())"
            self.activePlayerViewModel = vm
            player.play()
            let elapsed = String(format: "%.2f", Date().timeIntervalSince(preparationStartedAt))
            AppLogger.success("Offline playback started successfully in \(elapsed)s for item '\(itemID)'")
            return
        }

        // 2. Prepare remote playback asynchronously with Jellyfin server negotiation
        isPreparing = true
        loadingMessage = "Preparing Playback..."

        preparationTask = Task { @MainActor [weak self] in
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
                    let container = source.container?.lowercased() ?? "unknown"
                    let isAppleNative = ApplePlayableContainer.supports(container)
                    let directPlayAllowed = source.isSupportsDirectPlay == true && isAppleNative && (playbackInfo.maxStreamingBitrate == nil)

                    if let transURL = source.transcodingURL, !transURL.isEmpty {
                        // Server decided transcoding/remuxing is required
                        let cappedURL = PlaybackURL.applyingBitrateCap(playbackInfo.maxStreamingBitrate, to: transURL)
                        if let resolved = PlaybackURL.resolved(cappedURL, client: client) {
                            let authenticated = PlaybackURL.applyingAuthentication(resolved, token: client.configuration.accessToken)
                            negotiatedURL = authenticated
                            let method = (playbackInfo.maxStreamingBitrate != nil) ? "Transcode" : (source.isSupportsDirectStream == true ? "Direct Stream" : "Transcode")
                            diagnosticSummary = "\(method) • \(container) • \(source.bitrate.map { "\($0 / 1000) kbps" } ?? "Auto")"
                            AppLogger.info("Using server-provided transcoding URL (\(method)): \(authenticated.absoluteString)")
                        }
                    } else if directPlayAllowed {
                        // Direct Play
                        if let directURL = client.directVideoStreamURL(itemID: itemID, sessionID: playSessionID, mediaSourceID: source.id) {
                            let authenticated = PlaybackURL.applyingAuthentication(directURL, token: client.configuration.accessToken)
                            negotiatedURL = authenticated
                            diagnosticSummary = "Direct Play • \(container.uppercased())"
                            AppLogger.info("Direct play authorized by server for container '\(container)': \(authenticated.absoluteString)")
                        }
                    } else {
                        // Container requires remuxing or custom stream selection
                        AppLogger.info("Container '\(container)' or options require HLS delivery; requesting client-constructed transcoding URL")
                        if let hlsURL = self.transcodingURL(itemID: itemID, playbackInfo: playbackInfo, startTimeTicks: resumeTicks) {
                            negotiatedURL = hlsURL
                            diagnosticSummary = "Direct Stream • \(container)"
                            AppLogger.info("Generated client HLS transcoding URL: \(hlsURL.absoluteString)")
                        }
                    }
                } else {
                    AppLogger.warning("No media sources returned by server; falling back to client-constructed stream URL")
                    negotiatedURL = self.streamURL(itemID: itemID, playbackInfo: playbackInfo, startTimeTicks: resumeTicks)
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
                negotiatedURL = self.streamURL(itemID: itemID, playbackInfo: playbackInfo, startTimeTicks: resumeTicks)
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
                        self?.play(itemID: itemID, playbackInfo: playbackInfo, fromBeginning: fromBeginning, queue: queue)
                    }
                )
                return
            }

            AppLogger.info("Initializing AVPlayer with stream URL: \(url.absoluteString)")

            let playerItem: AVPlayerItem
            if url.isFileURL {
                playerItem = AVPlayerItem(url: url)
            } else {
                let asset = JellyfinAuthorization.asset(url: url, client: client)
                playerItem = AVPlayerItem(asset: asset)
            }

            let player = AVPlayer(playerItem: playerItem)

            if let resumeTicks, resumeTicks > 0 {
                let seconds = Double(resumeTicks) / 10_000_000.0
                let time = CMTime(seconds: seconds, preferredTimescale: 600)
                AppLogger.debug("Seeking AVPlayer to \(String(format: "%.2f", seconds))s")
                await player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
            }

            let vm = PlayerViewModel(itemID: itemID, playbackInfo: playbackInfo, player: player, queue: queue ?? [])
            vm.playbackDiagnosticSummary = diagnosticSummary
            self.activePlayerViewModel = vm
            self.isPreparing = false
            player.play()

            let totalElapsed = String(format: "%.2f", Date().timeIntervalSince(preparationStartedAt))
            AppLogger.success("Playback preparation reached ready in \(totalElapsed)s for item '\(itemID)'")
        }
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
