//
//  PlaybackReporter.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 11/24/26.
//

import Foundation
import JellyfinAPI
import LoggingKit

/// Manages Jellyfin playback lifecycle reporting (`/Sessions/Playing*`) and local progress sync
/// for a single `PlayerViewModel` session.
@MainActor
final class PlaybackReporter {

    enum ReportingState: Equatable, Sendable {
        case notReported
        case reported
        case stopped
    }

    private static let progressInterval: TimeInterval = 12.0
    private static let seekDebounceInterval: TimeInterval = 0.8

    private weak var client: JellyfinClient?
    private let userID: String?
    private let itemID: String
    private let mediaSourceID: String?
    private let playSessionID: String?
    private let playMethod: PlayMethod
    private let playbackStartTimeTicks: Int
    private let audioStreamIndex: Int?
    private let subtitleStreamIndex: Int?
    private let nowPlayingQueue: [QueueItem]?
    private let isEpisode: Bool

    private(set) var state: ReportingState = .notReported
    private(set) var lastKnownPositionTicks: Int
    private(set) var lastKnownDurationTicks: Int

    private var lastServerProgressSentAt: Date = .distantPast
    private var seekDebounceTask: Task<Void, Never>?
    private var lastReportedPaused: Bool?
    private var hasMarkedEnded: Bool = false
    private var startTask: Task<Void, Never>?

    init(
        client: JellyfinClient?,
        userID: String?,
        itemID: String,
        mediaSourceID: String?,
        playSessionID: String?,
        playMethod: PlayMethod,
        initialPositionTicks: Int,
        initialDurationTicks: Int,
        audioStreamIndex: Int?,
        subtitleStreamIndex: Int?,
        queue: [String],
        isEpisode: Bool
    ) {
        self.client = client
        self.userID = userID
        self.itemID = itemID
        self.mediaSourceID = mediaSourceID
        self.playSessionID = playSessionID
        self.playMethod = playMethod
        self.playbackStartTimeTicks = max(0, initialPositionTicks)
        self.lastKnownPositionTicks = max(0, initialPositionTicks)
        self.lastKnownDurationTicks = max(0, initialDurationTicks)
        self.audioStreamIndex = audioStreamIndex
        self.subtitleStreamIndex = subtitleStreamIndex
        self.nowPlayingQueue = queue.isEmpty ? nil : queue.map { QueueItem(id: $0) }
        self.isEpisode = isEpisode
    }

    // MARK: - Playback Lifecycle Events

    /// Reports session start (`POST /Sessions/Playing`) the first time playback enters `.playing`.
    func handlePlaybackStarted(isPaused: Bool = false) {
        guard state == .notReported else { return }
        state = .reported
        lastServerProgressSentAt = Date()
        lastReportedPaused = isPaused

        guard let client, NetworkMonitor.shared.isConnected else { return }
        let payload = makeStateInfo(isPaused: isPaused)
        let itemID = self.itemID
        let method = self.playMethod.rawValue
        let startTicks = self.lastKnownPositionTicks

        AppLogger.debug("Reporting playback start to Jellyfin for '\(itemID)' (positionTicks: \(startTicks), method: \(method))")
        startTask = Task {
            do {
                try await client.reportPlaybackStart(payload)
                AppLogger.debug("Successfully reported playback start for '\(itemID)'")
            } catch {
                AppLogger.warning("Failed to report playback start for '\(itemID)': \(error.localizedDescription)")
            }
        }
    }

    /// Updates cached timeline values from the periodic observer and sends a throttled progress report.
    func handlePeriodicTick(currentSeconds: Double, durationSeconds: Double, isPaused: Bool) {
        updateTimeline(positionSeconds: currentSeconds, durationSeconds: durationSeconds)

        guard state == .reported, !hasMarkedEnded, !isPaused else { return }
        guard Date().timeIntervalSince(lastServerProgressSentAt) >= Self.progressInterval else { return }

        sendServerProgress(isPaused: false)
    }

    /// Immediately reports pause/resume transitions to Jellyfin and syncs local progress on pause.
    func handlePauseStateChanged(isPaused: Bool) {
        guard state == .reported, !hasMarkedEnded, lastReportedPaused != isPaused else { return }
        lastReportedPaused = isPaused

        sendServerProgress(isPaused: isPaused)
        if isPaused {
            postLocalProgressUpdate(forcePlayed: false)
        }
    }

    /// Debounced progress report when the user scrubs/seeks after playback has started.
    func handleUserSeek(positionSeconds: Double, durationSeconds: Double, isPaused: Bool) {
        updateTimeline(positionSeconds: positionSeconds, durationSeconds: durationSeconds)

        guard state == .reported, !hasMarkedEnded else { return }
        seekDebounceTask?.cancel()
        seekDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.seekDebounceInterval * 1_000_000_000))
            guard !Task.isCancelled, let self, self.state == .reported, !self.hasMarkedEnded else { return }
            self.seekDebounceTask = nil
            self.sendServerProgress(isPaused: self.lastReportedPaused ?? isPaused)
        }
    }

    /// Marks the item completed at its full duration and reports stop before advancing the queue.
    func handleNaturalCompletion() {
        hasMarkedEnded = true
        if lastKnownDurationTicks > 0 {
            lastKnownPositionTicks = lastKnownDurationTicks
        }
        stop(forcePlayed: true)
    }

    /// Idempotently reports playback stopped (`POST /Sessions/Playing/Stopped`), posts optimistic
    /// local progress, and refreshes authoritative server `UserData` (+ `NextUp` for episodes).
    func stop(forcePlayed: Bool = false) {
        seekDebounceTask?.cancel()
        seekDebounceTask = nil
        guard state != .stopped else { return }
        let wasReported = (state == .reported)
        state = .stopped

        guard wasReported || forcePlayed else { return }

        let finalTicks = lastKnownPositionTicks
        postLocalProgressUpdate(forcePlayed: forcePlayed)

        guard let client, NetworkMonitor.shared.isConnected else { return }

        let itemID = self.itemID
        let userID = self.userID
        let mediaSourceID = self.mediaSourceID
        let playSessionID = self.playSessionID
        let isEpisode = self.isEpisode
        let pendingStart = self.startTask

        let stopInfo = PlaybackStopInfo(
            itemID: itemID,
            mediaSourceID: mediaSourceID,
            playSessionID: playSessionID,
            positionTicks: finalTicks
        )

        AppLogger.info("Reporting playback stopped to Jellyfin for '\(itemID)' (positionTicks: \(finalTicks))")

        Task { @MainActor in
            _ = await pendingStart?.value

            do {
                try await client.reportPlaybackStopped(stopInfo)
                AppLogger.debug("Successfully reported playback stop for '\(itemID)'")
            } catch {
                AppLogger.warning("Failed to report playback stop for '\(itemID)': \(error.localizedDescription)")
            }

            if let refreshed = try? await client.fetchItem(itemID: itemID, userID: userID),
               let userData = refreshed.userData {
                ServerViewModel.shared.applyUserData([userData])
            }

            if isEpisode {
                await LibraryViewModel.shared.refreshNextUp()
            }
        }
    }

    // MARK: - Helpers

    private func updateTimeline(positionSeconds: Double, durationSeconds: Double) {
        if positionSeconds.isFinite, positionSeconds >= 0 {
            lastKnownPositionTicks = Int(positionSeconds * 10_000_000.0)
        }
        if durationSeconds.isFinite, durationSeconds > 0 {
            lastKnownDurationTicks = Int(durationSeconds * 10_000_000.0)
        }
    }

    private func sendServerProgress(isPaused: Bool) {
        lastServerProgressSentAt = Date()
        guard let client, NetworkMonitor.shared.isConnected else { return }

        let payload = makeStateInfo(isPaused: isPaused)
        let itemID = self.itemID
        Task {
            do {
                try await client.reportPlaybackProgress(payload)
            } catch {
                AppLogger.warning("Failed to report playback progress for '\(itemID)': \(error.localizedDescription)")
            }
        }
    }

    private func makeStateInfo(isPaused: Bool) -> PlaybackStateInfo {
        PlaybackStateInfo(
            audioStreamIndex: audioStreamIndex,
            canSeek: true,
            isPaused: isPaused,
            itemID: itemID,
            mediaSourceID: mediaSourceID,
            nowPlayingQueue: nowPlayingQueue,
            playMethod: playMethod,
            playSessionID: playSessionID,
            playbackStartTimeTicks: playbackStartTimeTicks > 0 ? playbackStartTimeTicks : nil,
            positionTicks: lastKnownPositionTicks,
            subtitleStreamIndex: subtitleStreamIndex
        )
    }

    private func postLocalProgressUpdate(forcePlayed: Bool) {
        let total = lastKnownDurationTicks
        let percent: Double = total > 0 ? (Double(lastKnownPositionTicks) / Double(total)) * 100.0 : 0.0
        let isPlayed = forcePlayed || percent >= 85.0

        NotificationCenter.default.post(
            name: .mediaProgressUpdated,
            object: itemID,
            userInfo: [
                "positionTicks": lastKnownPositionTicks,
                "durationTicks": total,
                "playedPercentage": percent,
                "isPlayed": isPlayed
            ]
        )
    }
}
