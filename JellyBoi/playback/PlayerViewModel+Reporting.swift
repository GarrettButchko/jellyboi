//
//  PlayerViewModel+Reporting.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 10/5/26.
//

import Foundation
import AVFoundation
import CoreMedia
import JellyfinAPI
import LoggingKit

extension PlayerViewModel {

    // MARK: - Periodic Reporting

    func startPeriodicReporting() {
        subscriptions.cancelPeriodicReporting()
        subscriptions.periodicReportTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.reportPlaybackProgress()
            }
        }
    }

    func reportPlaybackStart() async {
        guard let client, let itemID = request.item.id else { return }
        AppLogger.debug("Reporting playback start to Jellyfin (positionTicks: \(timeline.currentPositionTicks), method: \(streamContext.playMethod.rawValue))")
        let state = PlaybackStateInfo(
            canSeek: true,
            isPaused: false,
            itemID: itemID,
            mediaSourceID: streamContext.mediaSourceID,
            playMethod: streamContext.playMethod,
            playSessionID: streamContext.playSessionID,
            positionTicks: timeline.currentPositionTicks
        )
        do {
            try await client.reportPlaybackStart(state)
            reportingState = .reported
            AppLogger.debug("Successfully reported playback start")
        } catch {
            AppLogger.warning("Failed to report playback start: \(error.localizedDescription)")
        }
    }

    func reportPlaybackProgress() async {
        guard let client, let itemID = request.item.id else { return }
        let isPaused = now == .paused || player?.timeControlStatus == .paused
        let currentSeconds = timeline.currentSeconds
        let totalSeconds = timeline.durationSeconds
        let percent = timeline.progressPercent
        AppLogger.debug("Progress report: \(String(format: "%.1f", currentSeconds))s / \(String(format: "%.1f", totalSeconds))s (\(String(format: "%.1f", percent))%) [paused: \(isPaused)]")

        let state = PlaybackStateInfo(
            canSeek: true,
            isPaused: isPaused,
            itemID: itemID,
            mediaSourceID: streamContext.mediaSourceID,
            playMethod: streamContext.playMethod,
            playSessionID: streamContext.playSessionID,
            positionTicks: timeline.currentPositionTicks
        )
        do {
            try await client.reportPlaybackProgress(state)
        } catch {
            AppLogger.warning("Failed to report playback progress: \(error.localizedDescription)")
        }
        updateLocalProgress(positionTicks: timeline.currentPositionTicks)
    }

    func reportPlaybackStopped() {
        sendPlaybackStopped(positionTicks: timeline.currentPositionTicks)
    }

    func sendPlaybackStopped(positionTicks: Int) {
        guard reportingState == .reported, let client, let itemID = request.item.id else { return }
        reportingState = .stopped
        updateLocalProgress(positionTicks: positionTicks)
        let sessionID = streamContext.playSessionID
        let sourceID = streamContext.mediaSourceID
        AppLogger.info("Reporting playback stopped to Jellyfin (positionTicks: \(positionTicks))")
        Task.detached {
            let stopInfo = PlaybackStopInfo(
                itemID: itemID,
                mediaSourceID: sourceID,
                playSessionID: sessionID,
                positionTicks: positionTicks
            )
            do {
                try await client.reportPlaybackStopped(stopInfo)
                AppLogger.debug("Successfully reported playback stop to server")
            } catch {
                AppLogger.warning("Failed to report playback stop: \(error.localizedDescription)")
            }
        }
    }

    func updateLocalProgress(positionTicks: Int, forcePlayed: Bool = false) {
        guard let itemID = request.item.id else { return }
        let total = timeline.durationTicks > 0 ? timeline.durationTicks : (request.item.runTimeTicks.map { Int($0) } ?? 0)
        let percent: Double = total > 0 ? (Double(positionTicks) / Double(total)) * 100.0 : 0.0
        let isPlayed = forcePlayed || percent >= 85.0

        libraryViewModel?.updateProgress(for: itemID, positionTicks: positionTicks, totalTicks: total)

        NotificationCenter.default.post(
            name: .mediaProgressUpdated,
            object: itemID,
            userInfo: [
                "positionTicks": positionTicks,
                "durationTicks": total,
                "playedPercentage": percent,
                "isPlayed": isPlayed
            ]
        )
    }
}
