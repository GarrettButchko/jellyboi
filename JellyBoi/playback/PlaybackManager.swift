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

@Observable
@MainActor
final class PlaybackManager {
    static let shared = PlaybackManager()

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

    var client: JellyfinClient?
    var userID: String?
    weak var libraryViewModel: LibraryViewModel?

    // MARK: - Playback State & Presentation

    var status: PlaybackStatus {
        get {
            activePlayerViewModel?.status ?? internalStatus
        }
        set {
            internalStatus = newValue
        }
    }
    private var internalStatus: PlaybackStatus = .idle

    var loadingMessage: String = "Loading Stream…"
    var activePlayerViewModel: PlayerViewModel?
    var currentError: PlaybackErrorInfo?
    var showErrorAlert: Bool = false

    private var activeTask: Task<Void, Never>?

    // Preload state
    private(set) var preloadedPlayerViewModel: PlayerViewModel?
    private(set) var preloadingTask: Task<Bool, Never>?
    private(set) var preloadedRequestKey: String?
    private(set) var inFlightPreloadVM: PlayerViewModel?

    func preloadKey(
        item: BaseItemDto,
        fromBeginning: Bool,
        mediaSourceID: String?,
        audioStreamIndex: Int?,
        subtitleStreamIndex: Int?,
        maxBitrate: Int?
    ) -> String {
        let resumeTicks = fromBeginning ? 0 : item.resumePlaybackTicks
        return "\(item.id ?? "")-\(resumeTicks)-\(fromBeginning)-\(mediaSourceID ?? "")-\(audioStreamIndex ?? -1)-\(subtitleStreamIndex ?? -1)-\(maxBitrate ?? -1)"
    }

    func isPreloadCompatible(
        vm: PlayerViewModel,
        item: BaseItemDto,
        fromBeginning: Bool,
        mediaSourceID: String?,
        audioStreamIndex: Int?,
        subtitleStreamIndex: Int?,
        maxBitrate: Int?
    ) -> Bool {
        if vm.status == .ended { return false }
        if case .failed = vm.status { return false }

        guard let vmItemID = vm.request.item.id, let itemID = item.id else { return false }
        let matchesID = (vmItemID == itemID) || (item.type == .series && vm.request.item.seriesID == itemID)
        guard matchesID else { return false }

        guard vm.request.startFromBeginning == fromBeginning else { return false }
        if maxBitrate != vm.request.maxBitrate { return false }

        let vmSource = vm.request.mediaSourceID ?? vm.streamContext.mediaSourceID
        if let mediaSourceID, let vmSource, mediaSourceID != vmSource {
            return false
        }

        if let audioStreamIndex, let vmAudio = vm.request.audioStreamIndex, audioStreamIndex != vmAudio {
            return false
        }

        let reqSub = subtitleStreamIndex ?? -1
        let vmSub = vm.request.subtitleStreamIndex ?? -1
        if reqSub != vmSub && subtitleStreamIndex != nil && vm.request.subtitleStreamIndex != nil {
            return false
        }

        return true
    }

    private func resolvePlaybackTarget(
        item: BaseItemDto,
        fromBeginning: Bool,
        queue: [BaseItemDto]?,
        resolvedClient: JellyfinClient?,
        resolvedUserID: String?,
        resolvedLibrary: LibraryViewModel?
    ) async -> (targetItem: BaseItemDto, activeQueue: [BaseItemDto], errorMessage: String?)? {
        var targetItem = item
        var activeQueue: [BaseItemDto] = queue ?? []

        if targetItem.type == .boxSet {
            if !activeQueue.isEmpty, let playable = activeQueue.nextPlayableItem(fromBeginning: fromBeginning) {
                targetItem = playable
                AppLogger.info("Selected next playable item '\(targetItem.name ?? "Unknown")' from provided queue")
            } else if let resolved = await self.resolveNextItemInCollection(
                collection: targetItem,
                fromBeginning: fromBeginning,
                client: resolvedClient,
                userID: resolvedUserID,
                libraryViewModel: resolvedLibrary
            ) {
                targetItem = resolved.playable
                activeQueue = resolved.queue
                AppLogger.info("Resolved collection '\(item.name ?? "")' to next item '\(targetItem.name ?? "Unknown")'")
            } else {
                return (targetItem, activeQueue, "No movies or TV shows found in this collection.")
            }
        }

        if targetItem.type == .series {
            if !fromBeginning, let resumeEp = resolvedLibrary?.resumeShows.first(where: { $0.seriesID == targetItem.id }) {
                targetItem = resumeEp
                if activeQueue.isEmpty {
                    let cached = (resolvedLibrary?.episodes ?? [])
                        .filter { $0.seriesID == targetItem.seriesID || $0.seriesID == item.id }
                        .sortedBySeasonAndEpisode()
                    activeQueue = cached.isEmpty ? [resumeEp] : cached
                } else if let matchIndex = activeQueue.firstIndex(where: { $0.id == resumeEp.id }) {
                    if activeQueue[matchIndex].resumePlaybackTicks == 0 && resumeEp.resumePlaybackTicks > 0 {
                        activeQueue[matchIndex].userData = resumeEp.userData
                    }
                }
                AppLogger.info("Resolved series '\(item.name ?? "")' to resume episode '\(targetItem.name ?? "Unknown")'")
            } else if let resolved = await self.resolvePlayableEpisode(
                for: targetItem,
                fromBeginning: fromBeginning,
                client: resolvedClient,
                userID: resolvedUserID,
                libraryViewModel: resolvedLibrary
            ) {
                targetItem = resolved.playable
                activeQueue = resolved.queue
                AppLogger.info("Resolved series '\(item.name ?? "")' to playable episode '\(targetItem.name ?? "Unknown")'")
            } else {
                return (targetItem, activeQueue, "No episodes found for this TV show.")
            }
        }

        if targetItem.type == .episode && activeQueue.isEmpty, let seriesID = targetItem.seriesID {
            let cached = (resolvedLibrary?.episodes ?? [])
                .filter { $0.seriesID == seriesID }
                .sortedBySeasonAndEpisode()
            if !cached.isEmpty {
                activeQueue = cached
            } else if let client = resolvedClient {
                let fetched = await client.fetchEpisodesOrEmpty(seriesID: seriesID, userID: resolvedUserID)
                activeQueue = fetched.sortedBySeasonAndEpisode()
            }
        }

        return (targetItem, activeQueue, nil)
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
        internalStatus = .idle
        currentError = nil
        showErrorAlert = false
    }

    private func makePlayerViewModel(
        targetItem: BaseItemDto,
        fromBeginning: Bool,
        localFileURL: URL?,
        mediaSourceID: String?,
        audioStreamIndex: Int?,
        subtitleStreamIndex: Int?,
        maxBitrate: Int?,
        activeQueue: [BaseItemDto],
        client: JellyfinClient?,
        userID: String?,
        libraryViewModel: LibraryViewModel?
    ) -> PlayerViewModel {
        let resolvedIndex = activeQueue.firstIndex(where: { $0.id == targetItem.id }) ?? 0
        let resolvedLocalURL = localFileURL ?? targetItem.id.flatMap { DownloadManager.shared.playableLocalFileURL(for: $0) }

        let request = PlaybackRequest(
            item: targetItem,
            startFromBeginning: fromBeginning,
            localFileURL: resolvedLocalURL,
            mediaSourceID: mediaSourceID,
            audioStreamIndex: audioStreamIndex,
            subtitleStreamIndex: subtitleStreamIndex,
            maxBitrate: maxBitrate,
            queue: activeQueue,
            initialQueueIndex: resolvedIndex
        )

        return PlayerViewModel(
            request: request,
            client: client,
            userID: userID,
            libraryViewModel: libraryViewModel,
            queue: activeQueue,
            initialQueueIndex: resolvedIndex
        )
    }

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
        if activePlayerViewModel != nil || status.isPreparing { return }

        let key = preloadKey(
            item: item,
            fromBeginning: fromBeginning,
            mediaSourceID: mediaSourceID,
            audioStreamIndex: audioStreamIndex,
            subtitleStreamIndex: subtitleStreamIndex,
            maxBitrate: maxBitrate
        )

        if preloadedRequestKey == key {
            return
        }

        if let existingVM = preloadedPlayerViewModel,
           isPreloadCompatible(
               vm: existingVM,
               item: item,
               fromBeginning: fromBeginning,
               mediaSourceID: mediaSourceID,
               audioStreamIndex: audioStreamIndex,
               subtitleStreamIndex: subtitleStreamIndex,
               maxBitrate: maxBitrate
           ) {
            preloadedRequestKey = key
            AppLogger.info("Existing preloaded player for '\(item.name ?? "")' is compatible; preserving")
            return
        }

        if let inFlightVM = inFlightPreloadVM,
           isPreloadCompatible(
               vm: inFlightVM,
               item: item,
               fromBeginning: fromBeginning,
               mediaSourceID: mediaSourceID,
               audioStreamIndex: audioStreamIndex,
               subtitleStreamIndex: subtitleStreamIndex,
               maxBitrate: maxBitrate
           ) {
            preloadedRequestKey = key
            AppLogger.info("In-flight preload for '\(item.name ?? "")' is compatible; preserving")
            return
        }

        cancelPreload()

        let resolvedClient = client ?? self.client
        let resolvedUserID = userID ?? self.userID
        let resolvedLibrary = libraryViewModel ?? self.libraryViewModel

        preloadedRequestKey = key
        internalStatus = .preloading
        AppLogger.info("Starting background preload for '\(item.name ?? "Unknown")'")

        preloadingTask = Task { @MainActor [weak self] in
            guard let self else { return false }
            defer {
                self.inFlightPreloadVM = nil
            }
            guard let resolved = await self.resolvePlaybackTarget(
                item: item,
                fromBeginning: fromBeginning,
                queue: queue,
                resolvedClient: resolvedClient,
                resolvedUserID: resolvedUserID,
                resolvedLibrary: resolvedLibrary
            ), resolved.errorMessage == nil else {
                if self.internalStatus == .preloading {
                    self.internalStatus = .idle
                }
                return false
            }

            guard !Task.isCancelled else {
                if self.internalStatus == .preloading {
                    self.internalStatus = .idle
                }
                return false
            }

            let targetItem = resolved.targetItem
            let activeQueue = resolved.activeQueue

            let vm = self.makePlayerViewModel(
                targetItem: targetItem,
                fromBeginning: fromBeginning,
                localFileURL: localFileURL,
                mediaSourceID: mediaSourceID,
                audioStreamIndex: audioStreamIndex,
                subtitleStreamIndex: subtitleStreamIndex,
                maxBitrate: maxBitrate,
                activeQueue: activeQueue,
                client: resolvedClient,
                userID: resolvedUserID,
                libraryViewModel: resolvedLibrary
            )
            self.inFlightPreloadVM = vm

            let success = await vm.prepare(mode: .preload)
            guard !Task.isCancelled else {
                vm.cleanup()
                if self.internalStatus == .preloading {
                    self.internalStatus = .idle
                }
                return false
            }

            if success {
                self.preloadedPlayerViewModel = vm
                self.internalStatus = .ready
                AppLogger.success("Preload ready for '\(targetItem.name ?? "Unknown")'")
                return true
            } else {
                vm.cleanup()
                self.preloadedPlayerViewModel = nil
                self.preloadedRequestKey = nil
                if self.internalStatus == .preloading {
                    self.internalStatus = .idle
                }
                return false
            }
        }
    }

    func cancelPreload() {
        guard !status.isPreparing && activePlayerViewModel == nil else {
            return
        }
        if let task = preloadingTask {
            task.cancel()
            preloadingTask = nil
        }
        if let vm = inFlightPreloadVM {
            vm.cleanup()
            inFlightPreloadVM = nil
        }
        if let vm = preloadedPlayerViewModel {
            AppLogger.info("Cleaning up preloaded player")
            vm.cleanup()
            preloadedPlayerViewModel = nil
        }
        preloadedRequestKey = nil
        if internalStatus == .preloading || internalStatus == .ready {
            internalStatus = .idle
        }
    }

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

        let resolvedClient = client ?? self.client
        let resolvedUserID = userID ?? self.userID
        let resolvedLibrary = libraryViewModel ?? self.libraryViewModel

        AppLogger.info("Requesting playback for '\(item.name ?? "Unknown")' (fromBeginning: \(fromBeginning))")

        if status.isPreparing && activeTask != nil {
            AppLogger.warning("Playback request ignored: already preparing playback")
            return
        }

        let key = preloadKey(
            item: item,
            fromBeginning: fromBeginning,
            mediaSourceID: mediaSourceID,
            audioStreamIndex: audioStreamIndex,
            subtitleStreamIndex: subtitleStreamIndex,
            maxBitrate: maxBitrate
        )

        // Fast path 1: Matching preload is already ready
        if let preloadedVM = preloadedPlayerViewModel,
           (preloadedRequestKey == key || isPreloadCompatible(
               vm: preloadedVM,
               item: item,
               fromBeginning: fromBeginning,
               mediaSourceID: mediaSourceID,
               audioStreamIndex: audioStreamIndex,
               subtitleStreamIndex: subtitleStreamIndex,
               maxBitrate: maxBitrate
           )) {
            AppLogger.success("Instant launch from preloaded player for '\(item.name ?? "")'")
            self.preloadedPlayerViewModel = nil
            self.preloadedRequestKey = nil
            self.preloadingTask = nil
            self.inFlightPreloadVM = nil

            self.resetActivePlayback()
            self.activePlayerViewModel = preloadedVM
            return
        }

        // Fast path 2: Matching preload is currently in flight
        let isInFlightCompatible = inFlightPreloadVM.map {
            isPreloadCompatible(
                vm: $0,
                item: item,
                fromBeginning: fromBeginning,
                mediaSourceID: mediaSourceID,
                audioStreamIndex: audioStreamIndex,
                subtitleStreamIndex: subtitleStreamIndex,
                maxBitrate: maxBitrate
            )
        } ?? false

        if (preloadedRequestKey == key || isInFlightCompatible), let ongoingPreload = preloadingTask {
            AppLogger.info("Awaiting in-flight preload for '\(item.name ?? "")'")
            self.preloadedRequestKey = nil
            self.preloadingTask = nil

            self.resetActivePlayback()
            self.status = .preparing
            loadingMessage = "Loading Stream…"

            activeTask = Task { @MainActor [weak self] in
                guard let self else { return }
                let success = await ongoingPreload.value
                guard !Task.isCancelled else {
                    self.status = .idle
                    return
                }
                if success, let preloadedVM = self.preloadedPlayerViewModel {
                    self.preloadedPlayerViewModel = nil
                    self.activePlayerViewModel = preloadedVM
                    return
                }
                if let preloadedVM = self.preloadedPlayerViewModel {
                    preloadedVM.cleanup()
                    self.preloadedPlayerViewModel = nil
                }
                self.startFullPlayback(
                    item: item,
                    fromBeginning: fromBeginning,
                    resolvedClient: resolvedClient,
                    resolvedUserID: resolvedUserID,
                    resolvedLibrary: resolvedLibrary,
                    localFileURL: localFileURL,
                    mediaSourceID: mediaSourceID,
                    audioStreamIndex: audioStreamIndex,
                    subtitleStreamIndex: subtitleStreamIndex,
                    maxBitrate: maxBitrate,
                    queue: queue
                )
            }
            return
        }

        cancelPreload()
        resetActivePlayback()
        status = .preparing
        loadingMessage = "Loading Stream…"

        startFullPlayback(
            item: item,
            fromBeginning: fromBeginning,
            resolvedClient: resolvedClient,
            resolvedUserID: resolvedUserID,
            resolvedLibrary: resolvedLibrary,
            localFileURL: localFileURL,
            mediaSourceID: mediaSourceID,
            audioStreamIndex: audioStreamIndex,
            subtitleStreamIndex: subtitleStreamIndex,
            maxBitrate: maxBitrate,
            queue: queue
        )
    }

    private func startFullPlayback(
        item: BaseItemDto,
        fromBeginning: Bool,
        resolvedClient: JellyfinClient?,
        resolvedUserID: String?,
        resolvedLibrary: LibraryViewModel?,
        localFileURL: URL?,
        mediaSourceID: String?,
        audioStreamIndex: Int?,
        subtitleStreamIndex: Int?,
        maxBitrate: Int?,
        queue: [BaseItemDto]?
    ) {
        status = .preparing
        activeTask = Task { @MainActor [weak self] in
            guard let self else { return }
            guard let resolved = await self.resolvePlaybackTarget(
                item: item,
                fromBeginning: fromBeginning,
                queue: queue,
                resolvedClient: resolvedClient,
                resolvedUserID: resolvedUserID,
                resolvedLibrary: resolvedLibrary
            ) else {
                self.status = .idle
                return
            }

            if let errorMsg = resolved.errorMessage {
                self.status = .failed(reason: errorMsg)
                self.currentError = PlaybackErrorInfo(
                    title: "Playback Error",
                    message: errorMsg,
                    retryAction: { [weak self] in
                        self?.play(
                            item: item,
                            fromBeginning: fromBeginning,
                            client: resolvedClient,
                            userID: resolvedUserID,
                            libraryViewModel: resolvedLibrary,
                            localFileURL: localFileURL,
                            mediaSourceID: mediaSourceID,
                            audioStreamIndex: audioStreamIndex,
                            subtitleStreamIndex: subtitleStreamIndex,
                            maxBitrate: maxBitrate,
                            queue: queue
                        )
                    }
                )
                self.showErrorAlert = true
                return
            }

            let targetItem = resolved.targetItem
            let activeQueue = resolved.activeQueue

            let vm = self.makePlayerViewModel(
                targetItem: targetItem,
                fromBeginning: fromBeginning,
                localFileURL: localFileURL,
                mediaSourceID: mediaSourceID,
                audioStreamIndex: audioStreamIndex,
                subtitleStreamIndex: subtitleStreamIndex,
                maxBitrate: maxBitrate,
                activeQueue: activeQueue,
                client: resolvedClient,
                userID: resolvedUserID,
                libraryViewModel: resolvedLibrary
            )

            let success = await vm.prepare(mode: .immediate)
            guard !Task.isCancelled else {
                vm.cleanup()
                self.status = .idle
                return
            }

            if success {
                AppLogger.success("Playback prepared successfully, presenting native player")
                self.activePlayerViewModel = vm
            } else {
                let err = vm.status.errorMessage ?? "An unknown error occurred while preparing playback."
                AppLogger.error("Playback preparation failed: \(err)")
                vm.cleanup()
                self.status = .failed(reason: err)
                self.currentError = PlaybackErrorInfo(
                    title: "Playback Error",
                    message: err,
                    retryAction: { [weak self] in
                        self?.play(
                            item: item,
                            fromBeginning: fromBeginning,
                            client: resolvedClient,
                            userID: resolvedUserID,
                            libraryViewModel: resolvedLibrary,
                            localFileURL: localFileURL,
                            mediaSourceID: mediaSourceID,
                            audioStreamIndex: audioStreamIndex,
                            subtitleStreamIndex: subtitleStreamIndex,
                            maxBitrate: maxBitrate,
                            queue: queue
                        )
                    }
                )
                self.showErrorAlert = true
            }
        }
    }

    func playLocal(item: BaseItemDto, fileURL: URL, fromBeginning: Bool = false, queue: [BaseItemDto]? = nil) {
        guard item.id != nil else {
            AppLogger.warning("Cannot start local playback: Item ID is missing")
            return
        }
        AppLogger.info("Requesting local file playback for '\(item.name ?? "Unknown")' at \(fileURL.lastPathComponent)")
        play(
            item: item,
            fromBeginning: fromBeginning,
            client: client,
            userID: userID,
            libraryViewModel: libraryViewModel,
            localFileURL: fileURL,
            queue: queue
        )
    }

    func clearError() {
        currentError = nil
        showErrorAlert = false
        if case .failed = status {
            internalStatus = .idle
        }
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
        internalStatus = .ended
    }

    // MARK: - Playable Item Resolution

    private func resolveNextItemInCollection(
        collection: BaseItemDto,
        fromBeginning: Bool,
        client: JellyfinClient?,
        userID: String?,
        libraryViewModel: LibraryViewModel?
    ) async -> (playable: BaseItemDto, queue: [BaseItemDto])? {
        guard let collectionID = collection.id, let client else { return nil }
        let items = await client.fetchItemsOrEmpty(
            parameters: .collectionItems(collectionID: collectionID, userID: userID)
        )
        let sorted = items.sorted { a, b in
            let dateA = a.premiereDate ?? (a.productionYear.flatMap { Calendar.current.date(from: DateComponents(year: $0)) } ?? .distantPast)
            let dateB = b.premiereDate ?? (b.productionYear.flatMap { Calendar.current.date(from: DateComponents(year: $0)) } ?? .distantPast)
            if dateA != dateB {
                return dateA < dateB
            }
            return (a.sortName ?? a.name ?? "") < (b.sortName ?? b.name ?? "")
        }

        let filtered = sorted.filter { $0.type == .movie || $0.type == .series || $0.type == .episode }
        let targetList = filtered.isEmpty ? sorted : filtered

        let resolvedList: [BaseItemDto] = targetList.map { item in
            guard let id = item.id else { return item }
            return libraryViewModel?.movies.first(where: { $0.id == id })
                ?? libraryViewModel?.resumeShows.first(where: { $0.id == id })
                ?? libraryViewModel?.episodes.first(where: { $0.id == id })
                ?? libraryViewModel?.tvShows.first(where: { $0.id == id })
                ?? item
        }

        guard let playable = resolvedList.nextPlayableItem(fromBeginning: fromBeginning) else { return nil }
        return (playable, resolvedList)
    }

    private func resolvePlayableEpisode(
        for series: BaseItemDto,
        fromBeginning: Bool,
        client: JellyfinClient?,
        userID: String?,
        libraryViewModel: LibraryViewModel?
    ) async -> (playable: BaseItemDto, queue: [BaseItemDto])? {
        guard let seriesID = series.id else { return nil }

        let cached = (libraryViewModel?.episodes ?? [])
            .filter { $0.seriesID == seriesID }
            .sortedBySeasonAndEpisode()

        if !fromBeginning, let resumeEp = libraryViewModel?.resumeShows.first(where: { $0.seriesID == seriesID }) {
            let queue = cached.isEmpty ? [resumeEp] : cached
            return (resumeEp, queue)
        }

        if !cached.isEmpty, let playable = cached.nextPlayableItem(fromBeginning: fromBeginning) {
            return (playable, cached)
        }

        guard let client else { return nil }
        let result = await client.fetchEpisodesOrEmpty(seriesID: seriesID, userID: userID)

        let sorted = result.sortedBySeasonAndEpisode()

        guard let playable = sorted.nextPlayableItem(fromBeginning: fromBeginning) else { return nil }
        return (playable, sorted)
    }
}
