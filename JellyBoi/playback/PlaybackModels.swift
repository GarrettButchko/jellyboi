//
//  PlaybackModels.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 11/12/26.
//

import Foundation
import CoreGraphics
import UIKit
import AVFoundation
import JellyfinAPI
import LoggingKit

// MARK: - Playback Status & State

/// Represents the discrete lifecycle state of media playback in `PlayerViewModel`.
enum PlaybackStatus: Equatable, Sendable, CustomStringConvertible {
    /// Initialized; media preparation has not yet started.
    case idle

    /// Actively preloading media in the background (rate 0, muted/no audio session activation).
    case preloading

    /// Preparing media actively for foreground playback (buffering, fetching stream metadata).
    case preparing

    /// Media item is fully prepared and primed at its resume position, ready to be displayed.
    case ready

    /// Actively playing media.
    case playing

    /// Playback is paused.
    case paused

    /// Playback or preparation failed with a specific error message.
    case failed(reason: String)

    /// Playback finished or the player instance was dismissed/cleaned up.
    case ended

    // MARK: - Computed Properties

    /// Indicates whether the player is currently preloading content in the background.
    var isPreloading: Bool {
        self == .preloading
    }

    /// Indicates whether the player is actively preparing or preloading content.
    var isLoading: Bool {
        switch self {
        case .preloading, .preparing:
            return true
        default:
            return false
        }
    }

    /// Indicates whether media is actively preparing for foreground playback.
    var isPreparing: Bool {
        self == .preparing
    }

    /// Indicates whether the player is currently in an active playback state.
    var isPlaying: Bool {
        self == .playing
    }

    /// Indicates whether media has loaded and is ready for interaction or presentation.
    var isReady: Bool {
        switch self {
        case .ready, .playing, .paused:
            return true
        default:
            return false
        }
    }

    /// Returns the failure error description if in the `.failed` state.
    var errorMessage: String? {
        if case .failed(let reason) = self {
            return reason
        }
        return nil
    }

    /// Indicates whether playback has reached a terminal state (ended or failed).
    var isTerminal: Bool {
        switch self {
        case .failed, .ended:
            return true
        default:
            return false
        }
    }

    var description: String {
        switch self {
        case .idle:
            return "idle"
        case .preloading:
            return "preloading"
        case .preparing:
            return "preparing"
        case .ready:
            return "ready"
        case .playing:
            return "playing"
        case .paused:
            return "paused"
        case .failed(let reason):
            return "failed(\(reason))"
        case .ended:
            return "ended"
        }
    }
}

// MARK: - PlayerViewModel Nested Types

extension PlayerViewModel {
    /// Defines the mode for media item preparation.
    enum PreparationMode: Sendable {
        /// Foreground playback; configures the audio session and prepares the player for immediate viewing.
        case immediate

        /// Background preloading; leaves audio deactivated and player paused at rate 0 for fast switching.
        case preload
    }

    /// Represents the state of the "Up Next" / auto-play overlay and countdown.
    enum UpNextState: Equatable, Sendable {
        /// Overlay is hidden.
        case hidden

        /// Overlay is actively displaying countdown and filling progress.
        case countdown(secondsRemaining: Int, progressFraction: Double)

        /// User explicitly dismissed the overlay for the current item.
        case dismissed

        /// Whether the overlay is currently visible to the user.
        var isVisible: Bool {
            if case .countdown = self { return true }
            return false
        }

        /// Number of seconds remaining before auto-play advances.
        var secondsRemaining: Int {
            if case .countdown(let sec, _) = self { return sec }
            return 0
        }

        /// Progress fraction from 0.0 to 1.0 representing elapsed countdown.
        var progressFraction: Double {
            if case .countdown(_, let prog) = self { return prog }
            return 0.0
        }

        /// Whether the overlay has been dismissed for the current media item.
        var isDismissed: Bool {
            self == .dismissed
        }
    }

    /// Represents the activation state of the AVAudioSession for media playback.
    enum AudioSessionState: Equatable, Sendable {
        /// Audio session is inactive / not configured by this player.
        case inactive
        /// Audio session has been actively configured and started.
        case active

        var isActive: Bool {
            self == .active
        }
    }

    /// Represents the state of the poster artwork image used in Now Playing metadata.
    enum ArtworkState: Equatable, @unchecked Sendable {
        /// No artwork loaded or fetch not requested.
        case none
        /// Artwork is actively being fetched.
        case loading
        /// Artwork image successfully loaded and available.
        case loaded(UIImage)

        var image: UIImage? {
            if case .loaded(let img) = self { return img }
            return nil
        }

        var isLoading: Bool {
            self == .loading
        }
    }

    /// Represents the reporting lifecycle of playback with the Jellyfin server.
    enum ReportingState: Equatable, Sendable {
        /// Initial playback start has not yet been reported.
        case notReported
        /// Playback start has been reported and periodic reporting is active.
        case reported
        /// Playback has reported stop / ended.
        case stopped

        var isReported: Bool {
            self == .reported
        }
    }

    /// Represents whether the initial resume position seek has completed.
    enum SeekState: Equatable, Sendable {
        /// Initial resume seek is pending.
        case pending
        /// Initial resume seek has been applied (or not needed).
        case applied

        var isApplied: Bool {
            self == .applied
        }
    }
}

// MARK: - Playback Timeline & Stream Context

/// Represents the playback timeline and position in ticks (10,000,000 ticks/sec).
struct PlaybackTimeline: Equatable, Sendable {
    var currentPositionTicks: Int = 0
    var initialResumeTicks: Int = 0
    var durationTicks: Int = 0

    var currentSeconds: Double {
        Double(currentPositionTicks) / 10_000_000.0
    }

    var initialResumeSeconds: Double {
        Double(initialResumeTicks) / 10_000_000.0
    }

    var durationSeconds: Double {
        Double(durationTicks) / 10_000_000.0
    }

    var progressFraction: Double {
        durationTicks > 0 ? min(1.0, max(0.0, Double(currentPositionTicks) / Double(durationTicks))) : 0.0
    }

    var progressPercent: Double {
        progressFraction * 100.0
    }
}

/// Encapsulates server streaming session identifiers, active source information, and video stream attributes.
struct ActiveStreamContext: Equatable, Sendable {
    var playSessionID: String?
    var mediaSourceID: String?
    var mediaSource: MediaSourceInfo?
    var maxBitrate: Int?
    var videoNaturalSize: CGSize?

    /// How the server is delivering this stream, as reported back in playback start/progress reports.
    ///
    /// `PlayMethod` comes from the JellyfinAPI package, so the three cases are documented here:
    /// - `.directPlay`: the server sends the original file untouched and AVPlayer reads it natively.
    ///   Cheapest option — no server CPU work and no transcoding delay. Requires an Apple-native
    ///   container (MP4/M4V/MOV) plus compatible video and audio codecs.
    /// - `.directStream`: the container is repackaged (remuxed) but the video and audio are copied
    ///   without re-encoding — e.g. MKV to HLS/fMP4. Small CPU cost on the server, no quality loss.
    ///   Used when the codecs are fine but the container is not something AVPlayer can open directly.
    /// - `.transcode`: the server decodes and re-encodes at least one stream. Required when the codec
    ///   is unsupported, when the user picks a lower bitrate/quality, or when burning in subtitles.
    ///   Most expensive option — highest server CPU and the slowest start.
    var playMethod: PlayMethod = .directStream
}

// MARK: - Playback Error Info

/// Information describing a playback error and optional retry action for alert presentation.
struct PlaybackErrorInfo: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let retryAction: (() -> Void)?

    init(title: String, message: String, retryAction: (() -> Void)? = nil) {
        self.title = title
        self.message = message
        self.retryAction = retryAction
    }
}

// MARK: - Playback Request & Prepared Media

/// Encapsulates all parameters needed to initiate playback of an item.
struct PlaybackRequest: Identifiable {
    let id: String
    let item: BaseItemDto
    let startFromBeginning: Bool
    let localFileURL: URL?
    let mediaSourceID: String?
    let audioStreamIndex: Int?
    let subtitleStreamIndex: Int?
    let maxBitrate: Int?
    let queue: [BaseItemDto]
    let initialQueueIndex: Int

    init(
        item: BaseItemDto,
        startFromBeginning: Bool = false,
        localFileURL: URL? = nil,
        mediaSourceID: String? = nil,
        audioStreamIndex: Int? = nil,
        subtitleStreamIndex: Int? = nil,
        maxBitrate: Int? = nil,
        queue: [BaseItemDto] = [],
        initialQueueIndex: Int = 0
    ) {
        self.id = (item.id ?? UUID().uuidString) + (startFromBeginning ? "-start" : "-resume")
        self.item = item
        self.startFromBeginning = startFromBeginning
        self.localFileURL = localFileURL
        self.mediaSourceID = mediaSourceID
        self.audioStreamIndex = audioStreamIndex
        self.subtitleStreamIndex = subtitleStreamIndex
        self.maxBitrate = maxBitrate
        self.queue = queue
        self.initialQueueIndex = initialQueueIndex
    }
}

/// Holds a preloaded or prepared player item and associated streaming metadata ready for playback.
struct PreparedMedia {
    let request: PlaybackRequest
    let playerItem: AVPlayerItem
    let streamContext: ActiveStreamContext
    let artworkImage: UIImage?

    init(
        request: PlaybackRequest,
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

// MARK: - Player Subscriptions

/// Manages player-related observations, timers, and background tasks for unified lifecycle cleanup.
@MainActor
final class PlayerSubscriptions {
    var timeObserverToken: Any?
    var endObserver: NSObjectProtocol?
    var statusObserver: NSKeyValueObservation?
    var muteObserver: NSKeyValueObservation?
    var timeControlStatusObserver: NSKeyValueObservation?
    var artworkTask: Task<Void, Never>?
    var periodicReportTimer: Timer?

    func cancelAll(player: AVPlayer?) {
        cancelPeriodicReporting()
        cancelTimeObserver(player: player)
        cancelEndObserver()
        cancelKVOObservers()
        cancelArtworkTask()
    }

    func cancelPeriodicReporting() {
        periodicReportTimer?.invalidate()
        periodicReportTimer = nil
    }

    func cancelTimeObserver(player: AVPlayer?) {
        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
            timeObserverToken = nil
        }
    }

    func cancelEndObserver() {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
    }

    func cancelKVOObservers() {
        statusObserver?.invalidate()
        statusObserver = nil
        muteObserver?.invalidate()
        muteObserver = nil
        timeControlStatusObserver?.invalidate()
        timeControlStatusObserver = nil
    }

    func cancelArtworkTask() {
        artworkTask?.cancel()
        artworkTask = nil
    }
}

// MARK: - Preload Session

extension PlaybackManager {
    /// Encapsulates the background preloading lifecycle in `PlaybackManager`.
    enum PreloadSession {
        case idle
        case inFlight(key: String, vm: PlayerViewModel?, task: Task<Bool, Never>, startedAt: Date)
        case ready(key: String, vm: PlayerViewModel, startedAt: Date)

        var key: String? {
            switch self {
            case .idle: return nil
            case .inFlight(let key, _, _, _), .ready(let key, _, _): return key
            }
        }

        var viewModel: PlayerViewModel? {
            switch self {
            case .idle: return nil
            case .inFlight(_, let vm, _, _): return vm
            case .ready(_, let vm, _): return vm
            }
        }

        var startedAt: Date? {
            switch self {
            case .idle: return nil
            case .inFlight(_, _, _, let date): return date
            case .ready(_, _, let date): return date
            }
        }

        var isPreloading: Bool {
            if case .inFlight = self { return true }
            return false
        }

        var isReady: Bool {
            if case .ready = self { return true }
            return false
        }

        mutating func cancel() {
            switch self {
            case .idle:
                break
            case .inFlight(_, let vm, let task, _):
                task.cancel()
                vm?.cleanup()
            case .ready(_, let vm, _):
                AppLogger.info("Cleaning up preloaded player")
                vm.cleanup()
            }
            self = .idle
        }
    }
}
