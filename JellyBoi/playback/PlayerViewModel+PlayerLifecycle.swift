//
//  PlayerViewModel+PlayerLifecycle.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 10/5/26.
//

import Foundation
import CoreGraphics
import AVKit
import CoreMedia
import MediaPlayer
import JellyfinAPI
import LoggingKit

extension PlayerViewModel {

    // MARK: - Audio Session

    func configureAudioSession() async {
        guard audioSessionState != .active else { return }
        if await AudioSessionController.activateForPlayback() {
            audioSessionState = .active
        }
    }

    // MARK: - Cleanup

    func cleanup() {
        guard now != .ended else { return }

        now = .ended

        AppLogger.info("Cleaning up PlayerViewModel resources for '\(request.item.playbackTitle)'")

        subscriptions.cancelAll(player: player)

        artworkState = .none
        streamContext.videoNaturalSize = nil
        upNextState = .hidden

        if let preloaded = preloadedMedia {
            (preloaded.playerItem.asset as? AVURLAsset)?.cancelLoading()
        }

        preloadedMedia = nil
        nextItemState = .idle

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

        if audioSessionState == .active {
            AudioSessionController.deactivate()
            audioSessionState = .inactive
        }

        sendPlaybackStopped(positionTicks: timeline.currentPositionTicks)
    }

    // MARK: - Player Preparation

    func prepare(mode: PreparationMode = .immediate) async -> Bool {
        guard now != .ended else {
            AppLogger.warning("Aborted player preparation: already cleaned up")
            return false
        }
        guard !Task.isCancelled else { return false }

        now = (mode == .preload) ? .preloading : .preparing
        seekState = .pending
        AppLogger.info("Starting player preparation for '\(request.item.playbackTitle)' (mode: \(mode))")

        if mode == .immediate {
            await configureAudioSession()
        }

        await resolveQueueIfNeeded()
        guard !Task.isCancelled else { return false }

        guard let prepared = await prepareMediaItem(for: request) else {
            if Task.isCancelled {
                return false
            }
            if case .failed = now {
                // Keep the specific failure reason already set
            } else {
                now = .failed(reason: "Failed to prepare media item.")
            }
            return false
        }

        guard !Task.isCancelled else { return false }

        applyPreparedMedia(prepared)

        let avPlayer = createConfiguredPlayer(for: prepared.playerItem)
        self.player = avPlayer

        startAsyncArtworkFetchIfNeeded()
        attachPlayerObservers(to: avPlayer)
        observeItemDidPlayToEnd(for: prepared.playerItem)

        let isReady = await waitForReadinessWithRetries(
            player: avPlayer,
            prepared: prepared
        )

        guard !Task.isCancelled else { return false }

        if isReady {
            now = .ready
        } else if case .failed = now {
            // Keep the specific failure reason
        } else {
            now = .failed(reason: "Playback connection timed out. Please try again.")
        }
        return isReady
    }

    private func applyPreparedMedia(_ prepared: PreparedMedia) {
        self.streamContext = prepared.streamContext
        self.artworkState = prepared.artworkImage.map { .loaded($0) } ?? .none
    }

    private func createConfiguredPlayer(for playerItem: AVPlayerItem) -> AVPlayer {
        let avPlayer = AVPlayer(playerItem: playerItem)
        avPlayer.allowsExternalPlayback = true
        avPlayer.usesExternalPlaybackWhileExternalScreenIsActive = true
        if now.isPreloading {
            avPlayer.rate = 0.0
        }
        return avPlayer
    }

    private func attachPlayerObservers(to avPlayer: AVPlayer) {
        var lastNonZeroVolume: Float = 1.0
        subscriptions.muteObserver = avPlayer.observe(\.isMuted, options: [.new]) { player, _ in
            if player.isMuted {
                if player.volume > 0.0 {
                    lastNonZeroVolume = player.volume
                }
                player.isMuted = false
                player.volume = lastNonZeroVolume > 0.0 ? lastNonZeroVolume : 1.0
            }
        }

        subscriptions.timeControlStatusObserver = avPlayer.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            Task { @MainActor [weak self] in
                guard let self, self.now != .ended else { return }
                switch player.timeControlStatus {
                case .playing:
                    self.now = .playing
                case .paused:
                    if self.now == .playing {
                        self.now = .paused
                    }
                case .waitingToPlayAtSpecifiedRate:
                    break
                @unknown default:
                    break
                }
            }
        }

        subscriptions.timeObserverToken = avPlayer.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 4),
            queue: .main
        ) { [weak self] time in
            guard let self else { return }
            MainActor.assumeIsolated {
                let seconds = CMTimeGetSeconds(time)
                if seconds.isFinite && seconds >= 0 {
                    if self.seekState == .applied || self.timeline.initialResumeTicks == 0 {
                        self.timeline.currentPositionTicks = Int(seconds * 10_000_000.0)
                    }
                }
                if let dur = avPlayer.currentItem?.duration {
                    let durationSec = CMTimeGetSeconds(dur)
                    if durationSec.isFinite && durationSec > 0 {
                        self.timeline.durationTicks = Int(durationSec * 10_000_000.0)
                        if self.seekState != .applied && self.timeline.initialResumeTicks == 0 && !self.request.startFromBeginning {
                            if let percent = self.request.item.userData?.playedPercentage, percent > 0 {
                                let calculated = Int((Double(self.timeline.durationTicks) * percent) / 100.0)
                                self.timeline.initialResumeTicks = calculated
                                self.timeline.currentPositionTicks = calculated
                            }
                        }
                    }
                }
                self.checkUpNextTrigger(currentSeconds: seconds)
            }
        }
    }

    private func waitForReadinessWithRetries(
        player: AVPlayer,
        prepared: PreparedMedia
    ) async -> Bool {
        var activeItem = prepared.playerItem
        let maxMapRetries = 2
        let wasPreloading = now.isPreloading

        for attempt in 0...maxMapRetries {
            guard !Task.isCancelled else { return false }

            if attempt > 0 {
                AppLogger.warning("Retrying playback after map initialization timeout (attempt \(attempt + 1)/\(maxMapRetries + 1)). Waiting for server transcode cache...")
                self.now = wasPreloading ? .preloading : .preparing

                subscriptions.statusObserver?.invalidate()
                subscriptions.statusObserver = nil

                try? await Task.sleep(for: .milliseconds(800))
                guard !Task.isCancelled else { return false }

                let newItem = AVPlayerItem(asset: prepared.playerItem.asset)
                newItem.externalMetadata = prepared.playerItem.externalMetadata
                if let composition = prepared.playerItem.videoComposition {
                    newItem.videoComposition = composition
                }
                player.replaceCurrentItem(with: newItem)
                activeItem = newItem
            }

            let isReady = await waitForReadiness(playerItem: activeItem)
            guard !Task.isCancelled else { return false }

            if isReady {
                if attempt > 0 {
                    AppLogger.success("Playback recovered after retry attempt \(attempt + 1)")
                }
                return true
            }

            if !isMapTimeoutFailure(item: activeItem) {
                let errDesc = activeItem.error?.localizedDescription ?? "unknown"
                let nsErr = activeItem.error as NSError?
                let errCode = nsErr?.code ?? 0
                let errDomain = nsErr?.domain ?? "none"
                AppLogger.error("Unrecoverable playback error (code=\(errCode), domain=\(errDomain), reason=\(errDesc))")
                return false
            }
        }

        if !Task.isCancelled {
            AppLogger.error("Failed to achieve readiness after \(maxMapRetries + 1) attempts")
        }
        return false
    }

    // MARK: - Readiness & Initial Playback

    func waitForReadiness(playerItem: AVPlayerItem) async -> Bool {
        if playerItem.status == .readyToPlay {
            await applyReadyToPlay()
            return true
        }
        if playerItem.status == .failed {
            let err = playerItem.error?.localizedDescription ?? "Playback failed."
            self.now = .failed(reason: err)
            return false
        }

        let box = ReadinessBox()

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                box.setResume { val in
                    continuation.resume(returning: val)
                }

                subscriptions.statusObserver = playerItem.observe(\.status, options: [.initial, .new]) { [weak self] currentItem, _ in
                    Task { @MainActor [weak self] in
                        guard let self, !Task.isCancelled else { return }
                        switch currentItem.status {
                        case .readyToPlay:
                            AppLogger.success("PlayerItem is readyToPlay.")
                            await self.applyReadyToPlay()
                            _ = box.resume(returning: true)

                        case .failed:
                            guard !Task.isCancelled else {
                                _ = box.resume(returning: false)
                                return
                            }
                            if box.resume(returning: false) {
                                let err = currentItem.error?.localizedDescription ?? "Playback failed."
                                AppLogger.error("PlayerItem failed with error: \(err)")
                                if let log = currentItem.errorLog() {
                                    for event in log.events {
                                        AppLogger.error("AVPlayerItem error event: URI=\(event.uri ?? "nil"), status=\(event.errorStatusCode), domain=\(event.errorDomain), comment=\(event.errorComment ?? "nil")")
                                    }
                                }
                                self.now = .failed(reason: err)
                            }

                        case .unknown:
                            break
                        @unknown default:
                            break
                        }
                    }
                }
            }
        } onCancel: {
            _ = box.resume(returning: false)
        }
    }

    func isMapTimeoutFailure(item: AVPlayerItem) -> Bool {
        if let nsError = item.error as NSError? {
            if nsError.domain == "CoreMediaErrorDomain" && nsError.code == -12889 {
                return true
            }
        }
        if let log = item.errorLog() {
            for event in log.events {
                if event.errorStatusCode == -12889 {
                    return true
                }
                if let comment = event.errorComment, comment.localizedCaseInsensitiveContains("map") {
                    return true
                }
            }
        }
        return false
    }

    func applyInitialResumeSeekIfNeeded(logContext: String = "") async {
        guard seekState != .applied else { return }
        seekState = .applied
        guard timeline.initialResumeTicks > 0 else { return }

        let seconds = timeline.initialResumeSeconds
        let currentSec = CMTimeGetSeconds(player?.currentTime() ?? .zero)

        if abs(currentSec - seconds) > 2.0 {
            let label = logContext.isEmpty ? "Seeking" : "Seeking \(logContext)"
            AppLogger.info("\(label) to resume position: \(String(format: "%.1f", seconds))s (ticks: \(timeline.initialResumeTicks))")
            let targetTime = CMTime(seconds: seconds, preferredTimescale: 600)
            let tolerance = CMTime(seconds: 0.5, preferredTimescale: 600)
            await player?.seek(to: targetTime, toleranceBefore: tolerance, toleranceAfter: tolerance)
        }
        timeline.currentPositionTicks = timeline.initialResumeTicks
    }

    func applyReadyToPlay() async {
        let wasPreloading = now.isPreloading
        self.now = .ready
        if let current = self.player?.currentItem {
            let tracks = current.tracks
            let trackInfo = tracks.map { track -> String in
                let mediaType = track.assetTrack?.mediaType.rawValue ?? "unknown"
                return "\(mediaType) (isEnabled: \(track.isEnabled))"
            }
            AppLogger.info("PlayerItem ready with \(tracks.count) tracks: [\(trackInfo.joined(separator: ", "))]")

            let videoTracks = tracks.filter { $0.assetTrack?.mediaType == .video }
            if videoTracks.isEmpty {
                AppLogger.warning("PlayerItem has NO video tracks active. PresentationSize: \(current.presentationSize)")
            } else {
                for vt in videoTracks {
                    let size = (try? await vt.assetTrack?.load(.naturalSize)) ?? .zero
                    AppLogger.debug("Video track enabled: \(vt.isEnabled), size: \(size.width)x\(size.height)")
                }
            }

            if self.streamContext.videoNaturalSize == nil, let firstVideoTrack = videoTracks.compactMap({ $0.assetTrack }).first {
                if let size = try? await firstVideoTrack.load(.naturalSize), size.width > 0, size.height > 0 {
                    self.streamContext.videoNaturalSize = size
                }
            }

            await selectRequestedSubtitle(in: current)
        }
        await applyInitialResumeSeekIfNeeded()

        self.player?.rate = 0.0
        if wasPreloading {
            AppLogger.info("Preloaded media item is paused at resume position and ready to play")
            return
        }

        AppLogger.info("Media item is prepared and paused awaiting presentation")
    }

    func startPlaybackIfNeeded() async {
        guard now != .ended, now != .playing, let player = self.player else { return }
        AppLogger.info("Starting playback on view appearance for '\(request.item.playbackTitle)'")

        await configureAudioSession()

        player.play()
        self.now = .playing
        if let img = artworkState.image {
            updateNowPlayingInfo(with: img)
        }
        if reportingState != .reported {
            await self.reportPlaybackStart()
            self.startPeriodicReporting()
        }
    }
}
