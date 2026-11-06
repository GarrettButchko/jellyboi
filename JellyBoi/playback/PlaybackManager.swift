//
//  PlaybackManager.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 10/5/26.
//

import SwiftUI
import AVKit
import Observation
import Get
import JellyfinAPI
import LoggingKit
import StatusOverlayKit

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

    var isLoading: Bool = false
    var loadingMessage: String = "Loading Stream…"
    var activePlayerViewModel: PlayerViewModel?
    var currentError: PlaybackErrorInfo?
    var showErrorAlert: Bool = false

    private var activeTask: Task<Void, Never>?

    // Preload state
    private(set) var preloadedPlayerViewModel: PlayerViewModel?
    private(set) var preloadingTask: Task<Bool, Never>?
    private(set) var preloadedRequestKey: String?

    func preloadKey(
        item: BaseItemDto,
        fromBeginning: Bool,
        mediaSourceID: String?,
        audioStreamIndex: Int?,
        subtitleStreamIndex: Int?,
        maxBitrate: Int?
    ) -> String {
        "\(item.id ?? "")-\(fromBeginning)-\(mediaSourceID ?? "")-\(audioStreamIndex ?? -1)-\(subtitleStreamIndex ?? -1)-\(maxBitrate ?? -1)"
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
                AppLogger.info("Selected next playable item '\(targetItem.name ?? "Unknown")' from provided queue", tag: "PlaybackManager")
            } else if let resolved = await self.resolveNextItemInCollection(
                collection: targetItem,
                fromBeginning: fromBeginning,
                client: resolvedClient,
                userID: resolvedUserID,
                libraryViewModel: resolvedLibrary
            ) {
                targetItem = resolved.playable
                activeQueue = resolved.queue
                AppLogger.info("Resolved collection '\(item.name ?? "")' to next item '\(targetItem.name ?? "Unknown")'", tag: "PlaybackManager")
            } else {
                return (targetItem, activeQueue, "No movies or TV shows found in this collection.")
            }
        }

        if targetItem.type == .series {
            if !activeQueue.isEmpty, let playable = activeQueue.nextPlayableItem(fromBeginning: fromBeginning) {
                targetItem = playable
                AppLogger.info("Selected next playable episode '\(targetItem.name ?? "Unknown")' from provided queue", tag: "PlaybackManager")
            } else if let resolved = await self.resolvePlayableEpisode(
                for: targetItem,
                fromBeginning: fromBeginning,
                client: resolvedClient,
                userID: resolvedUserID,
                libraryViewModel: resolvedLibrary
            ) {
                targetItem = resolved.playable
                activeQueue = resolved.queue
                AppLogger.info("Resolved series '\(item.name ?? "")' to episode '\(targetItem.name ?? "Unknown")'", tag: "PlaybackManager")
            } else {
                return (targetItem, activeQueue, "No playable episodes found for this show.")
            }
        }

        if targetItem.type == .episode && activeQueue.isEmpty, let seriesID = targetItem.seriesID {
            let cached = (resolvedLibrary?.episodes ?? [])
                .filter { $0.seriesID == seriesID }
                .sortedBySeasonAndEpisode()
            if !cached.isEmpty {
                activeQueue = cached
            } else if let resolved = await self.resolvePlayableEpisode(
                for: BaseItemDto(id: seriesID),
                fromBeginning: false,
                client: resolvedClient,
                userID: resolvedUserID,
                libraryViewModel: resolvedLibrary
            ) {
                activeQueue = resolved.queue
            }
        }

        if !fromBeginning && targetItem.resumePlaybackTicks == 0 {
            if let id = targetItem.id,
               let match = resolvedLibrary?.movies.first(where: { $0.id == id })
                        ?? resolvedLibrary?.resumeShows.first(where: { $0.id == id })
                        ?? resolvedLibrary?.episodes.first(where: { $0.id == id }),
               match.resumePlaybackTicks > 0 {
                targetItem = match
            }
        }

        return (targetItem, activeQueue, nil)
    }

    private func resetActivePlayback() {
        activeTask?.cancel()
        if let current = activePlayerViewModel {
            AppLogger.info("Releasing existing player", tag: "PlaybackManager")
            current.cleanup()
            activePlayerViewModel = nil
        }
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
        if activePlayerViewModel != nil { return }

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

        cancelPreload()

        let resolvedClient = client ?? self.client
        let resolvedUserID = userID ?? self.userID
        let resolvedLibrary = libraryViewModel ?? self.libraryViewModel

        preloadedRequestKey = key
        AppLogger.info("Starting background preload for '\(item.name ?? "Unknown")'", tag: "PlaybackManager")

        preloadingTask = Task { @MainActor [weak self] in
            guard let self else { return false }
            guard let resolved = await self.resolvePlaybackTarget(
                item: item,
                fromBeginning: fromBeginning,
                queue: queue,
                resolvedClient: resolvedClient,
                resolvedUserID: resolvedUserID,
                resolvedLibrary: resolvedLibrary
            ), resolved.errorMessage == nil else {
                return false
            }

            guard !Task.isCancelled else { return false }

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

            let success = await vm.prepare(isPreload: true)
            guard !Task.isCancelled else {
                vm.cleanup()
                return false
            }

            if success {
                self.preloadedPlayerViewModel = vm
                AppLogger.success("Preload ready for '\(targetItem.name ?? "Unknown")'", tag: "PlaybackManager")
                return true
            } else {
                vm.cleanup()
                self.preloadedPlayerViewModel = nil
                self.preloadedRequestKey = nil
                return false
            }
        }
    }

    func cancelPreload() {
        guard !isLoading && activePlayerViewModel == nil else {
            return
        }
        if let task = preloadingTask {
            task.cancel()
            preloadingTask = nil
        }
        if let vm = preloadedPlayerViewModel {
            AppLogger.info("Cleaning up preloaded player", tag: "PlaybackManager")
            vm.cleanup()
            preloadedPlayerViewModel = nil
        }
        preloadedRequestKey = nil
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
            AppLogger.warning("Cannot start playback: Item ID is missing", tag: "PlaybackManager")
            return
        }

        let resolvedClient = client ?? self.client
        let resolvedUserID = userID ?? self.userID
        let resolvedLibrary = libraryViewModel ?? self.libraryViewModel

        AppLogger.info("Requesting playback for '\(item.name ?? "Unknown")' (fromBeginning: \(fromBeginning))", tag: "PlaybackManager")

        if isLoading && activeTask != nil {
            AppLogger.warning("Playback request ignored: already preparing playback", tag: "PlaybackManager")
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
        if preloadedRequestKey == key, let preloadedVM = preloadedPlayerViewModel {
            AppLogger.success("Instant launch from preloaded player for '\(item.name ?? "")'", tag: "PlaybackManager")
            self.preloadedPlayerViewModel = nil
            self.preloadedRequestKey = nil
            self.preloadingTask = nil

            self.resetActivePlayback()
            isLoading = false

            activeTask = Task { @MainActor [weak self] in
                guard let self else { return }
                await preloadedVM.startPlaybackFromPreload()
                self.activePlayerViewModel = preloadedVM
            }
            return
        }

        // Fast path 2: Matching preload is currently in flight
        if preloadedRequestKey == key, let ongoingPreload = preloadingTask {
            AppLogger.info("Awaiting in-flight preload for '\(item.name ?? "")'", tag: "PlaybackManager")
            self.preloadedRequestKey = nil
            self.preloadingTask = nil

            self.resetActivePlayback()
            withAnimation(statusOverlaySpring) {
                isLoading = true
            }
            loadingMessage = "Loading Stream…"

            activeTask = Task { @MainActor [weak self] in
                guard let self else { return }
                let success = await ongoingPreload.value
                guard !Task.isCancelled else {
                    withAnimation(statusOverlaySpring) {
                        self.isLoading = false
                    }
                    return
                }
                if success, let preloadedVM = self.preloadedPlayerViewModel {
                    self.preloadedPlayerViewModel = nil
                    await preloadedVM.startPlaybackFromPreload()
                    withAnimation(statusOverlaySpring) {
                        self.isLoading = false
                    }
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
        withAnimation(statusOverlaySpring) {
            isLoading = true
        }
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
                withAnimation(statusOverlaySpring) {
                    self.isLoading = false
                }
                return
            }

            if let errorMsg = resolved.errorMessage {
                withAnimation(statusOverlaySpring) {
                    self.isLoading = false
                }
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

            let success = await vm.prepare()
            guard !Task.isCancelled else {
                vm.cleanup()
                withAnimation(statusOverlaySpring) {
                    self.isLoading = false
                }
                return
            }

            withAnimation(statusOverlaySpring) {
                self.isLoading = false
            }

            if success {
                AppLogger.success("Playback prepared successfully, presenting native player", tag: "PlaybackManager")
                self.activePlayerViewModel = vm
            } else {
                let err = vm.errorMessage ?? "An unknown error occurred while preparing playback."
                AppLogger.error("Playback preparation failed: \(err)", tag: "PlaybackManager")
                vm.cleanup()
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
            AppLogger.warning("Cannot start local playback: Item ID is missing", tag: "PlaybackManager")
            return
        }
        AppLogger.info("Requesting local file playback for '\(item.name ?? "Unknown")' at \(fileURL.lastPathComponent)", tag: "PlaybackManager")

        resetActivePlayback()
        withAnimation(statusOverlaySpring) {
            isLoading = true
        }
        loadingMessage = "Loading Media…"

        activeTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let vm = self.makePlayerViewModel(
                targetItem: item,
                fromBeginning: fromBeginning,
                localFileURL: fileURL,
                mediaSourceID: nil,
                audioStreamIndex: nil,
                subtitleStreamIndex: nil,
                maxBitrate: nil,
                activeQueue: queue ?? [item],
                client: self.client,
                userID: self.userID,
                libraryViewModel: self.libraryViewModel
            )

            let success = await vm.prepare()
            guard !Task.isCancelled else {
                vm.cleanup()
                withAnimation(statusOverlaySpring) {
                    self.isLoading = false
                }
                return
            }

            withAnimation(statusOverlaySpring) {
                self.isLoading = false
            }

            if success {
                self.activePlayerViewModel = vm
            } else {
                let err = vm.errorMessage ?? "An error occurred while opening the local file."
                vm.cleanup()
                self.currentError = PlaybackErrorInfo(
                    title: "Playback Error",
                    message: err,
                    retryAction: { [weak self] in
                        self?.playLocal(item: item, fileURL: fileURL, fromBeginning: fromBeginning, queue: queue)
                    }
                )
                self.showErrorAlert = true
            }
        }
    }

    func clearError() {
        currentError = nil
        showErrorAlert = false
    }

    func stop() {
        #if os(iOS)
        OrientationHelper.lockOrientation(.portrait, rotateTo: .portrait)
        #endif
        activeTask?.cancel()
        activeTask = nil
        withAnimation(statusOverlaySpring) {
            isLoading = false
        }
        if let current = activePlayerViewModel {
            AppLogger.info("Stopping playback and releasing resources for '\(current.request.item.playbackTitle)'", tag: "PlaybackManager")
            current.cleanup()
        }
        activePlayerViewModel = nil
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
