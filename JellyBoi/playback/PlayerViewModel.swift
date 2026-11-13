//
//  PlayerViewModel.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 10/5/26.
//

import Foundation
import AVKit
import Observation
import JellyfinAPI
import LoggingKit

/// Owns the state of one foreground playback session.
///
/// This file is intentionally limited to state and initialisation. Preparation lives in
/// `PlayerViewModel+Preparation`, AVPlayer lifecycle in `PlayerViewModel+PlayerLifecycle`,
/// queue progression in `PlayerViewModel+Queue`, and so on.
@Observable
@MainActor
final class PlayerViewModel: Identifiable {

    let id: String = UUID().uuidString
    var request: PlaybackRequest
    let client: JellyfinClient?
    let userID: String?
    weak var libraryViewModel: LibraryViewModel?

    var queue: [BaseItemDto] = []
    var currentIndex: Int = 0

    // Playback state & presentation ("Now" and "Next")
    var player: AVPlayer?

    /// Discrete lifecycle state of the current media item being presented / played ("Now").
    var now: PlaybackStatus = .idle

    /// Lifecycle of the next queued item ("Next").
    var nextItemState: NextItemState = .idle

    /// Preloaded media item for the next queued item, if ready in memory.
    var preloadedMedia: PreparedMedia?

    var areControlsVisible: Bool = true

    var upNextState: UpNextState = .hidden
    var timeline: PlaybackTimeline = PlaybackTimeline()
    var streamContext: ActiveStreamContext = ActiveStreamContext()
    let subscriptions = PlayerSubscriptions()

    // MARK: - Playback Sub-States & Resource Tracking

    var audioSessionState: AudioSessionState = .inactive
    var artworkState: ArtworkState = .none
    var reportingState: ReportingState = .notReported
    var seekState: SeekState = .pending

    init(
        request: PlaybackRequest,
        client: JellyfinClient?,
        userID: String?,
        libraryViewModel: LibraryViewModel?
    ) {
        self.request = request
        self.client = client
        self.userID = userID
        self.libraryViewModel = libraryViewModel
        self.queue = request.queue
        self.currentIndex = request.initialQueueIndex

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

        AppLogger.info("Initialized PlayerViewModel for '\(request.item.name ?? "Unknown")' (ID: \(request.item.id ?? "nil"), resumeTicks: \(resume)) [Queue: \(request.queue.count) items, index: \(request.initialQueueIndex)]")
    }

    // MARK: - Aspect Ratio

    /// Display aspect ratio reported by the stream, the item, or a downloaded copy of it.
    public var targetAspectRatio: Double? {
        let streamAspect = streamContext.mediaSource?.mediaStreams?.first(where: { $0.type == .video })?.aspectRatio
            ?? request.item.mediaStreams?.first(where: { $0.type == .video })?.aspectRatio
            ?? request.item.aspectRatio
            ?? (request.item.id.flatMap { DownloadManager.shared.downloadItem(for: $0)?.item.mediaStreams?.first(where: { $0.type == .video })?.aspectRatio })
            ?? (request.item.id.flatMap { DownloadManager.shared.downloadItem(for: $0)?.item.aspectRatio })
        return AspectRatioParser.parse(streamAspect)
    }

    deinit {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                cleanup()
            }
        }
    }
}
