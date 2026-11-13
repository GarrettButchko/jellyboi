//
//  PlayerViewModel+Queue.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 10/5/26.
//

import Foundation
import CoreGraphics
import AVKit
import CoreMedia
import JellyfinAPI
import LoggingKit

extension PlayerViewModel {

    // MARK: - Queue & Navigation

    var nextItem: BaseItemDto? {
        guard currentIndex + 1 < queue.count else { return nil }
        return queue[currentIndex + 1]
    }

    func resolveQueueIfNeeded() async {
        guard queue.isEmpty, let client else { return }
        if request.item.type == .episode, let seriesID = request.item.seriesID {
            AppLogger.info("Resolving queue for series '\(request.item.seriesName ?? seriesID)'")
            let cached = (libraryViewModel?.episodes ?? [])
                .filter { $0.seriesID == seriesID }
                .sortedBySeasonAndEpisode()

            if !cached.isEmpty {
                self.queue = cached
                if let idx = cached.firstIndex(where: { $0.id == request.item.id }) {
                    self.currentIndex = idx
                }
                return
            }

            let result = await client.fetchEpisodesOrEmpty(seriesID: seriesID, userID: userID)
            if !result.isEmpty {
                let sorted = result.sortedBySeasonAndEpisode()
                self.queue = sorted
                if let idx = sorted.firstIndex(where: { $0.id == request.item.id }) {
                    self.currentIndex = idx
                }
            }
        }
    }

    func observeItemDidPlayToEnd(for item: AVPlayerItem) {
        subscriptions.cancelEndObserver()
        subscriptions.endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                AppLogger.info("Playback reached end of media item")
                self?.handlePlaybackFinished()
            }
        }
    }

    func makeNextPlaybackRequest(for next: BaseItemDto) -> PlaybackRequest {
        let resolvedLocalURL = next.id.flatMap { DownloadManager.shared.playableLocalFileURL(for: $0) }
        return PlaybackRequest(
            item: next,
            startFromBeginning: true,
            localFileURL: resolvedLocalURL
        )
    }

    // MARK: - Up Next & In-Place Progression

    func checkUpNextTrigger(currentSeconds: Double) {
        guard let dur = player?.currentItem?.duration else { return }
        let durationSec = CMTimeGetSeconds(dur)
        guard durationSec.isFinite && durationSec > 60 else { return }

        let remainingSec = durationSec - currentSeconds

        guard nextItem != nil else {
            if upNextState.isVisible {
                upNextState = .hidden
            }
            return
        }

        if remainingSec <= 30 && remainingSec >= 0 {
            let secRemaining = max(0, Int(round(remainingSec)))
            let progress = max(0.0, min(1.0, (30.0 - remainingSec) / 30.0))

            if !upNextState.isDismissed {
                upNextState = .countdown(secondsRemaining: secRemaining, progressFraction: progress)
            }

            if preloadedMedia == nil && !nextItemState.isPreloading {
                Task {
                    await preloadNextMedia()
                }
            }
        } else {
            if upNextState.isVisible {
                upNextState = .hidden
            }
        }
    }

    func dismissUpNextOverlay() {
        upNextState = .dismissed
    }

    func preloadNextMedia() async {
        guard let nextItem = nextItem, !nextItemState.isPreloading, preloadedMedia == nil else { return }
        nextItemState = .preloading
        defer {
            if nextItemState == .preloading {
                nextItemState = .idle
            }
        }

        AppLogger.info("Preloading next media item: '\(nextItem.name ?? "Unknown")'")

        let nextReq = makeNextPlaybackRequest(for: nextItem)

        if let prepared = await prepareMediaItem(for: nextReq) {
            self.preloadedMedia = prepared
            self.nextItemState = .ready
            AppLogger.success("Successfully preloaded next item: '\(nextItem.name ?? "Unknown")'")
        }
    }

    func playNextItem() async {
        guard let nextItem = nextItem, nextItemState != .preparing else { return }
        let preloaded = preloadedMedia
        nextItemState = .preparing
        defer {
            nextItemState = .idle
            preloadedMedia = nil
        }

        AppLogger.info("Transitioning to next item: '\(nextItem.name ?? "Unknown")'")

        handlePlaybackFinished(isSwitchingToNext: true)

        upNextState = .hidden

        let mediaToPlay: PreparedMedia
        if let preloaded, preloaded.request.item.id == nextItem.id {
            mediaToPlay = preloaded
            AppLogger.info("Using preloaded player item for '\(nextItem.name ?? "Unknown")'")
        } else {
            now = .preparing
            let nextReq = makeNextPlaybackRequest(for: nextItem)
            guard let newlyPrepared = await prepareMediaItem(for: nextReq) else {
                now = .failed(reason: "Failed to prepare next item for playback")
                AppLogger.error("Failed to prepare next item for playback")
                return
            }
            mediaToPlay = newlyPrepared
        }

        self.request = mediaToPlay.request
        let dur = mediaToPlay.request.item.runTimeTicks.map { Int($0) } ?? 0
        let nextResume = mediaToPlay.request.startFromBeginning ? 0 : mediaToPlay.request.item.resumePlaybackTicks
        self.timeline = PlaybackTimeline(currentPositionTicks: nextResume, initialResumeTicks: nextResume, durationTicks: dur)
        self.streamContext = mediaToPlay.streamContext
        self.artworkState = mediaToPlay.artworkImage.map { .loaded($0) } ?? .none
        self.reportingState = .notReported
        self.seekState = .pending
        self.currentIndex += 1

        player?.replaceCurrentItem(with: mediaToPlay.playerItem)

        observeItemDidPlayToEnd(for: mediaToPlay.playerItem)

        if let img = artworkState.image {
            updateNowPlayingInfo(with: img)
        }

        await selectRequestedSubtitle(in: mediaToPlay.playerItem)

        await applyInitialResumeSeekIfNeeded(logContext: "queue item")

        player?.play()
        self.now = .playing
        await reportPlaybackStart()
        startPeriodicReporting()
        AppLogger.success("Now playing next item: '\(request.item.playbackTitle)'")
    }

    func handlePlaybackFinished(isSwitchingToNext: Bool = false) {
        let finalTicks = timeline.durationTicks > 0 ? timeline.durationTicks : timeline.currentPositionTicks
        timeline.currentPositionTicks = finalTicks
        AppLogger.success("Playback marked as watched (100%)")
        updateLocalProgress(positionTicks: finalTicks, forcePlayed: true)
        sendPlaybackStopped(positionTicks: finalTicks)

        if !isSwitchingToNext {
            if nextItem != nil {
                Task { @MainActor [weak self] in
                    await self?.playNextItem()
                }
            } else {
                AppLogger.info("Final item in queue completed. Dismissing player.")
                PlaybackManager.shared.stop()
            }
        }
    }
}
