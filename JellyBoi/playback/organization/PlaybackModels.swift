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

// MARK: - Playback Target

/// Everything needed to start a playback session, with the caller's optional overrides already
/// merged with `PlaybackManager`'s session defaults.
///
/// Callers are expected to hand in a concrete playable item (a movie, episode, or special
/// feature) plus its queue; resolving containers to their next playable child is the job of the
/// view model that owns the item, not of the playback layer.
struct PlaybackTarget {
    let item: BaseItemDto
    let fromBeginning: Bool
    let client: JellyfinClient?
    let userID: String?
    let libraryViewModel: LibraryViewModel?
    let localFileURL: URL?
    let mediaSourceID: String?
    let audioStreamIndex: Int?
    let subtitleStreamIndex: Int?
    let maxBitrate: Int?
    let queue: [BaseItemDto]?

    /// Whether a player prepared for `other` would present exactly the same stream.
    ///
    /// Stream selections are compared literally: `nil` means "server default", which is not
    /// interchangeable with an explicit selection. Reusing a preload made for a different
    /// subtitle or audio track would silently present the wrong stream.
    func isCompatible(with other: PlaybackTarget) -> Bool {
        guard let itemID = item.id, other.item.id == itemID else { return false }
        return fromBeginning == other.fromBeginning
            && mediaSourceID == other.mediaSourceID
            && audioStreamIndex == other.audioStreamIndex
            && subtitleStreamIndex == other.subtitleStreamIndex
            && maxBitrate == other.maxBitrate
    }

    /// A copy of this target aimed at a different item, keeping the same session and stream options.
    func retargeted(to newItem: BaseItemDto, queue: [BaseItemDto]?) -> PlaybackTarget {
        PlaybackTarget(
            item: newItem,
            fromBeginning: fromBeginning,
            client: client,
            userID: userID,
            libraryViewModel: libraryViewModel,
            localFileURL: localFileURL,
            mediaSourceID: mediaSourceID,
            audioStreamIndex: audioStreamIndex,
            subtitleStreamIndex: subtitleStreamIndex,
            maxBitrate: maxBitrate,
            queue: queue
        )
    }
}

extension PlaybackTarget {
    /// Builds the player view model for this target, preferring a downloaded local file when one exists.
    @MainActor
    func makePlayerViewModel() -> PlayerViewModel {
        let activeQueue = queue ?? []
        let index = activeQueue.firstIndex { $0.id == item.id } ?? 0
        let resolvedLocalURL = localFileURL ?? item.id.flatMap { DownloadManager.shared.playableLocalFileURL(for: $0) }

        let request = PlaybackRequest(
            item: item,
            startFromBeginning: fromBeginning,
            localFileURL: resolvedLocalURL,
            mediaSourceID: mediaSourceID,
            audioStreamIndex: audioStreamIndex,
            subtitleStreamIndex: subtitleStreamIndex,
            maxBitrate: maxBitrate,
            queue: activeQueue,
            initialQueueIndex: index
        )

        return PlayerViewModel(
            request: request,
            client: client,
            userID: userID,
            libraryViewModel: libraryViewModel
        )
    }
}
