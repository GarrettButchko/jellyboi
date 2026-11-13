//
//  PlaybackStatus.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 11/13/26.
//

import Foundation
import UIKit

// MARK: - Playback Status

/// Represents the discrete lifecycle state of the media item currently presented by `PlayerViewModel`.
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

    /// Indicates whether the player is currently in an active playback state.
    var isPlaying: Bool {
        self == .playing
    }

    /// Returns the failure error description if in the `.failed` state.
    var errorMessage: String? {
        if case .failed(let reason) = self {
            return reason
        }
        return nil
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

    /// Lifecycle of the next queued item. Only the phases the queue logic needs; presentation of
    /// the next item is handled by `now` once `playNextItem()` swaps it in.
    enum NextItemState: Equatable, Sendable {
        /// Nothing preloaded for the next item yet.
        case idle

        /// The next item's player item is being prepared in the background.
        case preloading

        /// The next item is being swapped into the player.
        case preparing

        /// The next item's player item is prepared and waiting to be played.
        case ready

        var isPreloading: Bool {
            self == .preloading
        }
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

// MARK: - PlaybackManager Nested Types

extension PlaybackManager {
    /// Coordination phase of the foreground playback session.
    ///
    /// This is intentionally narrower than `PlaybackStatus`: the manager only needs to know
    /// whether it is launching a player. Once a player exists, its own `now` status drives the UI.
    enum SessionPhase: Equatable, Sendable {
        case idle
        case preparing
        case playing
        case failed(reason: String)

        var isPreparing: Bool {
            self == .preparing
        }

        var isFailed: Bool {
            if case .failed = self {
                return true
            }
            return false
        }
    }
}
