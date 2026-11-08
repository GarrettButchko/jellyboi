//
//  PlayerViewModel.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 10/5/26.
//

import Foundation
import CoreGraphics
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

    let id: String = UUID().uuidString
    var request: PlaybackManager.PlaybackRequest
    let client: JellyfinClient?
    let userID: String?
    weak var libraryViewModel: LibraryViewModel?

    var queue: [BaseItemDto] = []
    var currentIndex: Int = 0

    // Playback state & presentation
    var player: AVPlayer?
    var status: PlaybackStatus = .idle
    var areControlsVisible: Bool = true

    var upNextState: UpNextState = .hidden
    var queueTransition: QueueTransitionState = .idle
    var timeline: PlaybackTimeline = PlaybackTimeline()
    var streamContext: ActiveStreamContext = ActiveStreamContext()
    let subscriptions = PlayerSubscriptions()

    var hasActivatedAudioSession: Bool = false
    var loadedArtworkImage: UIImage?
    var hasReportedStart: Bool = false
    var hasAppliedInitialSeek: Bool = false

    struct PreparedMedia {
        let request: PlaybackManager.PlaybackRequest
        let playerItem: AVPlayerItem
        let streamContext: ActiveStreamContext
        let artworkImage: UIImage?

        init(
            request: PlaybackManager.PlaybackRequest,
            playerItem: AVPlayerItem,
            streamContext: ActiveStreamContext,
            artworkImage: UIImage? = nil
        ) {
            self.request = request
            self.playerItem = playerItem
            self.streamContext = streamContext
            self.artworkImage = artworkImage
        }
    }

    init(
        request: PlaybackManager.PlaybackRequest,
        client: JellyfinClient?,
        userID: String?,
        libraryViewModel: LibraryViewModel?,
        queue: [BaseItemDto] = [],
        initialQueueIndex: Int = 0
    ) {
        self.request = request
        self.client = client
        self.userID = userID
        self.libraryViewModel = libraryViewModel
        self.queue = queue
        self.currentIndex = initialQueueIndex

        let dur = request.item.runTimeTicks.map { Int($0) } ?? 0
        let resume = request.startFromBeginning ? 0 : request.item.resumePlaybackTicks
        self.timeline = PlaybackTimeline(currentPositionTicks: resume, initialResumeTicks: resume, durationTicks: dur)
        self.streamContext = ActiveStreamContext(
            playSessionID: nil,
            mediaSourceID: request.mediaSourceID,
            mediaSource: nil,
            maxBitrate: request.maxBitrate,
            videoNaturalSize: nil,
            playMethod: .directStream
        )

        AppLogger.info("Initialized PlayerViewModel for '\(request.item.name ?? "Unknown")' (ID: \(request.item.id ?? "nil"), resumeTicks: \(resume)) [Queue: \(queue.count) items, index: \(initialQueueIndex)]")
    }

    // MARK: - Aspect Ratio Helpers

    public var targetAspectRatio: Double? {
        let streamAspect = streamContext.mediaSource?.mediaStreams?.first(where: { $0.type == .video })?.aspectRatio
            ?? request.item.mediaStreams?.first(where: { $0.type == .video })?.aspectRatio
            ?? request.item.aspectRatio
            ?? (request.item.id.flatMap { DownloadManager.shared.downloadItem(for: $0)?.item.mediaStreams?.first(where: { $0.type == .video })?.aspectRatio })
            ?? (request.item.id.flatMap { DownloadManager.shared.downloadItem(for: $0)?.item.aspectRatio })
        return Self.parseAspectRatio(streamAspect)
    }

    public nonisolated static func parseAspectRatio(_ raw: String?) -> Double? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        if raw.contains(":") {
            let parts = raw.split(separator: ":")
            if parts.count == 2, let num = Double(parts[0]), let den = Double(parts[1]), den > 0 {
                return num / den
            }
        }
        if raw.contains("/") {
            let parts = raw.split(separator: "/")
            if parts.count == 2, let num = Double(parts[0]), let den = Double(parts[1]), den > 0 {
                return num / den
            }
        }
        if let val = Double(raw), val > 0 {
            return val
        }
        return nil
    }

    // MARK: - Audio Session Management

    func configureAudioSession() async {
        guard !hasActivatedAudioSession else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, policy: .longFormVideo)
            try await activateAudioSession()
            hasActivatedAudioSession = true
            AppLogger.debug("Configured AVAudioSession (.playback, .moviePlayback, .longFormVideo)")
        } catch {
            AppLogger.warning("Long-form video audio session policy failed: \(error.localizedDescription); falling back")
            do {
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
                try await activateAudioSession()
                hasActivatedAudioSession = true
            } catch {
                AppLogger.error("Audio session configuration failed: \(error.localizedDescription)", error)
            }
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
                    try await Task.detached {
                        try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
                    }.value
                }
            } catch {
                AppLogger.debug("Audio session deactivation info: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Lifecycle & Cleanup

    func cleanup() {
        guard status != .ended else { return }
        status = .ended
        AppLogger.info("Cleaning up PlayerViewModel resources for '\(request.item.playbackTitle)'")

        subscriptions.cancelAll(player: player)

        loadedArtworkImage = nil
        streamContext.videoNaturalSize = nil

        upNextState = .hidden
        if let preloaded = queueTransition.preloadedMedia {
            (preloaded.playerItem.asset as? AVURLAsset)?.cancelLoading()
        }
        queueTransition = .idle

        #if canImport(MediaPlayer)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        #endif

        player?.pause()
        player?.rate = 0.0

        if let currentItem = player?.currentItem {
            (currentItem.asset as? AVURLAsset)?.cancelLoading()
        }
        player?.replaceCurrentItem(with: nil)
        player = nil

        if hasActivatedAudioSession {
            deactivateAudioSession()
            hasActivatedAudioSession = false
        }

        sendPlaybackStopped(positionTicks: timeline.currentPositionTicks)
    }

    // MARK: - Playback Diagnostics

    public var playbackDiagnosticSummary: String {
        var items: [String] = []
        items.append("Method: \(streamContext.playMethod.rawValue)")
        if let local = request.localFileURL {
            items.append("Local: \(local.lastPathComponent)")
            let size = (try? FileManager.default.attributesOfItem(atPath: local.path)[.size] as? Int64) ?? 0
            if size > 0 {
                items.append("Size: \(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))")
            }
        } else {
            items.append("Source: Server Stream")
        }
        if let current = player?.currentItem {
            let tracks = current.tracks
            let videoTracks = tracks.filter { $0.assetTrack?.mediaType == .video }
            let audioTracks = tracks.filter { $0.assetTrack?.mediaType == .audio }
            let presentationSize = current.presentationSize
            let videoSize = streamContext.videoNaturalSize ?? (presentationSize != .zero ? presentationSize : nil)
            if videoTracks.isEmpty {
                items.append("Video: None (Audio Only)")
            } else if let v = videoTracks.first {
                if let size = videoSize {
                    let w = Int(size.width)
                    let h = Int(size.height)
                    items.append("Video: \(w)x\(h) [\(v.isEnabled ? "Active" : "Disabled")]")
                } else {
                    if let at = v.assetTrack {
                        Task { @MainActor [weak self] in
                            if let size = try? await at.load(.naturalSize), size.width > 0, size.height > 0 {
                                self?.streamContext.videoNaturalSize = size
                            }
                        }
                    }
                    items.append("Video: Track Present [\(v.isEnabled ? "Active" : "Disabled")]")
                }
            } else {
                items.append("Video: Track Present")
            }
            items.append("Audio: \(audioTracks.count) track(s)")
        }
        return items.joined(separator: " • ")
    }

    deinit {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                cleanup()
            }
        }
    }
}
