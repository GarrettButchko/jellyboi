//
//  PlaybackManager.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 10/5/26.
//

import Foundation
import AVKit
import Observation
import Get
import JellyfinAPI
import LoggingKit

@Observable
@MainActor
final class PlaybackManager {

    static let shared = PlaybackManager()

    // MARK: - Dependencies & Session State

    var client: JellyfinClient?
    var userID: String?
    weak var libraryViewModel: LibraryViewModel?
    /// The currently active player view model driving foreground playback and UI presentation.
    var activePlayerViewModel: PlayerViewModel?
    /// Coordination phase of the foreground playback session.
    private(set) var sessionPhase: SessionPhase = .idle

    let loadingMessage = "Loading Stream…"
    var currentError: PlaybackErrorInfo? {
        didSet {
            if currentError == nil, sessionPhase.isFailed {
                sessionPhase = .idle
            }
        }
    }

    /// Background preload for the item the user is most likely to play next, if any.
    private var preloadJob: PreloadJob?
    private var activeTask: Task<Void, Never>?

    /// Indicates whether playback is actively preparing for foreground display.
    var isPreparing: Bool {
        sessionPhase.isPreparing
    }

    // MARK: - Preload Job

    /// A background-prepared player that can be handed straight to the UI.
    private struct PreloadJob {
        enum Phase {
            /// `prepare(mode: .preload)` is still running.
            case loading
            /// The player is prepared and paused at its resume position.
            case ready
        }

        let id: UUID
        let target: PlaybackTarget
        var phase: Phase = .loading
        var player: PlayerViewModel?
        var task: Task<Bool, Never>?
    }

    // MARK: - Preloading

    /// Prepares a player in the background so a later `play` for the same target can present instantly.
    func preload(
        item: BaseItemDto,
        fromBeginning: Bool = false,
        client: JellyfinClient? = nil,
        userID: String? = nil,
        libraryViewModel: LibraryViewModel? = nil,
        localFileURL: URL? = nil,
        mediaSourceID: String? = nil,
        audioStreamIndex: Int? = nil,
        subtitleStreamIndex: Int? = nil,
        maxBitrate: Int? = nil,
        queue: [BaseItemDto]? = nil
    ) {
        guard item.id != nil else { return }
        guard activePlayerViewModel == nil, !isPreparing else { return }

        let target = makeTarget(
            item: item,
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
        guard let target = resolvedTarget(target) else { return }

        if let job = preloadJob {
            guard !job.target.isCompatible(with: target) else {
                AppLogger.info("Existing preload for '\(item.name ?? "")' is still valid; preserving")
                return
            }
            discardPreload()
        }

        AppLogger.info("Starting background preload for '\(item.name ?? "Unknown")'")

        let jobID = UUID()
        let task = Task { @MainActor [weak self] in
            guard let self else { return false }
            let startedAt = Date()

            let vm = target.makePlayerViewModel()
            self.updatePreloadJob(id: jobID) { $0.player = vm }

            let success = await vm.prepare(mode: .preload)
            guard success, !Task.isCancelled else {
                vm.cleanup()
                self.clearPreloadJob(id: jobID)
                return false
            }

            self.updatePreloadJob(id: jobID) { $0.phase = .ready }
            let elapsed = Date().timeIntervalSince(startedAt)
            AppLogger.success("Preload ready for '\(target.item.name ?? "Unknown")' (\(String(format: "%.2f", elapsed))s)")
            return true
        }
        preloadJob = PreloadJob(id: jobID, target: target, task: task)
    }

    /// Cancels and releases any background preload that is not already being presented.
    func cancelPreload() {
        guard !isPreparing, activePlayerViewModel == nil else { return }
        discardPreload()
    }

    private func discardPreload() {
        guard let job = preloadJob else { return }
        preloadJob = nil
        job.task?.cancel()
        job.player?.cleanup()
    }

    /// Mutates the current preload job only if it is still the one identified by `id`.
    private func updatePreloadJob(id: UUID, _ mutate: (inout PreloadJob) -> Void) {
        guard var job = preloadJob, job.id == id else { return }
        mutate(&job)
        preloadJob = job
    }

    private func clearPreloadJob(id: UUID) {
        guard preloadJob?.id == id else { return }
        preloadJob = nil
    }

    // MARK: - Playback

    func play(
        item: BaseItemDto,
        fromBeginning: Bool = false,
        client: JellyfinClient? = nil,
        userID: String? = nil,
        libraryViewModel: LibraryViewModel? = nil,
        localFileURL: URL? = nil,
        mediaSourceID: String? = nil,
        audioStreamIndex: Int? = nil,
        subtitleStreamIndex: Int? = nil,
        maxBitrate: Int? = nil,
        queue: [BaseItemDto]? = nil
    ) {
        guard item.id != nil else {
            AppLogger.warning("Cannot start playback: Item ID is missing")
            return
        }

        play(makeTarget(
            item: item,
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
        ))
    }

    private func play(_ target: PlaybackTarget) {
        guard let resolved = resolvedTarget(target) else {
            fail("No playable item found for this title.", retry: target)
            return
        }

        if let job = preloadJob, job.target.isCompatible(with: resolved) {
            if job.phase == .ready, let player = job.player {
                AppLogger.success("Instant launch from preloaded player for '\(resolved.item.name ?? "")'")
                preloadJob = nil
                resetActivePlayback()
                activePlayerViewModel = player
                sessionPhase = .playing
                return
            }

            if let task = job.task {
                awaitPreload(task, jobID: job.id, target: resolved, retry: target)
                return
            }
        }

        discardPreload()
        resetActivePlayback()
        startPlayback(resolved, retry: target)
    }

    /// Waits for an in-flight preload, presenting its player on success or starting over on failure.
    private func awaitPreload(
        _ preload: Task<Bool, Never>,
        jobID: UUID,
        target: PlaybackTarget,
        retry retryTarget: PlaybackTarget
    ) {
        AppLogger.info("Awaiting in-flight preload for '\(target.item.name ?? "")'")

        resetActivePlayback()
        sessionPhase = .preparing

        activeTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let success = await preload.value

            guard !Task.isCancelled else {
                self.sessionPhase = .idle
                return
            }

            if success,
               let job = self.preloadJob,
               job.id == jobID,
               job.phase == .ready,
               let player = job.player {
                self.preloadJob = nil
                self.activePlayerViewModel = player
                self.sessionPhase = .playing
                return
            }

            self.clearPreloadJob(id: jobID)
            self.startPlayback(target, retry: retryTarget)
        }
    }

    private func startPlayback(_ target: PlaybackTarget, retry retryTarget: PlaybackTarget) {
        sessionPhase = .preparing
        activeTask = Task { @MainActor [weak self] in
            guard let self else { return }

            let vm = target.makePlayerViewModel()
            let success = await vm.prepare(mode: .immediate)

            guard !Task.isCancelled else {
                vm.cleanup()
                self.sessionPhase = .idle
                return
            }

            guard success else {
                let reason = vm.now.errorMessage ?? "An unknown error occurred while preparing playback."
                AppLogger.error("Playback preparation failed: \(reason)")
                vm.cleanup()
                self.fail(reason, retry: retryTarget)
                return
            }

            AppLogger.success("Playback prepared successfully, presenting native player")
            self.activePlayerViewModel = vm
            self.sessionPhase = .playing
        }
    }

    private func resetActivePlayback() {
        activeTask?.cancel()
        activeTask = nil
        let current = activePlayerViewModel
        activePlayerViewModel = nil
        if let current {
            AppLogger.info("Releasing existing player")
            current.cleanup()
        }
        sessionPhase = .idle
        currentError = nil
    }

    private func fail(_ reason: String, retry target: PlaybackTarget?) {
        sessionPhase = .failed(reason: reason)

        var retryAction: (() -> Void)?
        if let target {
            retryAction = { [weak self] in self?.play(target) }
        }
        currentError = PlaybackErrorInfo(
            title: "Playback Error",
            message: reason,
            retryAction: retryAction
        )
    }

    func clearError() {
        currentError = nil
    }

    func stop() {
        #if os(iOS)
        OrientationHelper.lockOrientation(.portrait, rotateTo: .portrait)
        #endif
        activeTask?.cancel()
        activeTask = nil
        let current = activePlayerViewModel
        activePlayerViewModel = nil
        if let current {
            AppLogger.info("Stopping playback and releasing resources for '\(current.request.item.playbackTitle)'")
            current.cleanup()
        }
        sessionPhase = .idle
    }

    // MARK: - Target Construction

    /// Resolves a container to the concrete item that should be played, using cached library data only.
    ///
    /// The detail view normally hands over the exact episode it wants to play, so this only covers
    /// requests made before that view has its episode list. No network request happens here: a
    /// fetch inside the preload path would defeat the point of preloading. A box set that reaches
    /// this point already had its items loaded, so an unresolved container means there is nothing
    /// playable to show.
    private func resolvedTarget(_ target: PlaybackTarget) -> PlaybackTarget? {
        guard target.item.type == .series else {
            return target.item.type == .boxSet ? nil : target
        }
        guard let seriesID = target.item.id,
              let library = target.libraryViewModel
        else { return nil }

        let episodes = library.episodes(forSeriesID: seriesID).sortedBySeasonAndEpisode()
        guard !episodes.isEmpty else { return nil }

        if !target.fromBeginning,
           let resume = library.resumeShows.first(where: { $0.seriesID == seriesID }),
           let index = episodes.firstIndex(where: { $0.id == resume.id }) {
            // Keep the queue's copy so the index matches, but take the server's resume position.
            var episode = episodes[index]
            if episode.resumePlaybackTicks == 0 && resume.resumePlaybackTicks > 0 {
                episode.userData = resume.userData
            }
            return target.retargeted(to: episode, queue: episodes)
        }

        guard let playable = episodes.nextPlayableItem(fromBeginning: target.fromBeginning) else {
            return nil
        }
        return target.retargeted(to: playable, queue: episodes)
    }

    /// Merges the caller's optional overrides with the manager's current session defaults.
    private func makeTarget(
        item: BaseItemDto,
        fromBeginning: Bool,
        client: JellyfinClient?,
        userID: String?,
        libraryViewModel: LibraryViewModel?,
        localFileURL: URL?,
        mediaSourceID: String?,
        audioStreamIndex: Int?,
        subtitleStreamIndex: Int?,
        maxBitrate: Int?,
        queue: [BaseItemDto]?
    ) -> PlaybackTarget {
        PlaybackTarget(
            item: item,
            fromBeginning: fromBeginning,
            client: client ?? self.client,
            userID: userID ?? self.userID,
            libraryViewModel: libraryViewModel ?? self.libraryViewModel,
            localFileURL: localFileURL,
            mediaSourceID: mediaSourceID,
            audioStreamIndex: audioStreamIndex,
            subtitleStreamIndex: subtitleStreamIndex,
            maxBitrate: maxBitrate,
            queue: queue
        )
    }
}
