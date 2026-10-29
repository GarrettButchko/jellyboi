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

        activeTask?.cancel()
        currentError = nil
        showErrorAlert = false
        withAnimation(statusOverlaySpring) {
            isLoading = true
        }
        loadingMessage = "Loading Stream…"

        activeTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var targetItem = item
            var activeQueue: [BaseItemDto] = queue ?? []

            if targetItem.type == .boxSet {
                if let resolved = await self.resolveNextItemInCollection(
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
                    withAnimation(statusOverlaySpring) {
                        self.isLoading = false
                    }
                    self.currentError = PlaybackErrorInfo(
                        title: "Playback Error",
                        message: "No movies or TV shows found in this collection.",
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
            }

            if targetItem.type == .series {
                if let resolved = await self.resolvePlayableEpisode(
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
                    withAnimation(statusOverlaySpring) {
                        self.isLoading = false
                    }
                    self.currentError = PlaybackErrorInfo(
                        title: "Playback Error",
                        message: "No playable episodes found for this show.",
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
            }

            if targetItem.type == .episode && activeQueue.isEmpty, let seriesID = targetItem.seriesID {
                if let resolved = await self.resolvePlayableEpisode(
                    for: BaseItemDto(id: seriesID),
                    fromBeginning: false,
                    client: resolvedClient,
                    userID: resolvedUserID,
                    libraryViewModel: resolvedLibrary
                ) {
                    activeQueue = resolved.queue
                }
            }

            let resolvedIndex: Int = {
                if let idx = activeQueue.firstIndex(where: { $0.id == targetItem.id }) {
                    return idx
                }
                return 0
            }()

            if !fromBeginning && targetItem.resumePlaybackTicks == 0 {
                if let id = targetItem.id,
                   let match = resolvedLibrary?.movies.first(where: { $0.id == id })
                            ?? resolvedLibrary?.resumeShows.first(where: { $0.id == id })
                            ?? resolvedLibrary?.episodes.first(where: { $0.id == id }),
                   match.resumePlaybackTicks > 0 {
                    targetItem = match
                }
            }

            let resolvedLocalURL: URL? = {
                #if DEBUG
                if DebugSettings.shared.forceStreamFallback {
                    AppLogger.debug("[DebugSettings] forceStreamFallback is active; bypassing local file", tag: "PlaybackManager")
                    return nil
                }
                #endif
                if let localFileURL { return localFileURL }
                guard let id = targetItem.id, DownloadManager.shared.isLocallyPlayable(id: id) else { return nil }
                return DownloadManager.shared.localFileURL(for: id)
            }()
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
            let vm = PlayerViewModel(
                request: request,
                client: resolvedClient,
                userID: resolvedUserID,
                libraryViewModel: resolvedLibrary,
                queue: activeQueue,
                initialQueueIndex: resolvedIndex
            )

            let success = await vm.prepare()
            guard !Task.isCancelled else {
                vm.cleanup()
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

        activeTask?.cancel()
        currentError = nil
        showErrorAlert = false
        withAnimation(statusOverlaySpring) {
            isLoading = true
        }
        loadingMessage = "Loading Media…"

        activeTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let activeQueue = queue ?? [item]
            let resolvedIndex = activeQueue.firstIndex(where: { $0.id == item.id }) ?? 0
            let request = PlaybackRequest(
                item: item,
                startFromBeginning: fromBeginning,
                localFileURL: fileURL,
                queue: activeQueue,
                initialQueueIndex: resolvedIndex
            )
            let vm = PlayerViewModel(
                request: request,
                client: self.client,
                userID: self.userID,
                libraryViewModel: self.libraryViewModel,
                queue: activeQueue,
                initialQueueIndex: resolvedIndex
            )

            let success = await vm.prepare()
            guard !Task.isCancelled else {
                vm.cleanup()
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
            AppLogger.info("Stopping playback and releasing resources for '\(current.title)'", tag: "PlaybackManager")
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
            .sorted { a, b in
                let sA = a.parentIndexNumber ?? 1
                let sB = b.parentIndexNumber ?? 1
                if sA != sB { return sA < sB }
                return (a.indexNumber ?? 1) < (b.indexNumber ?? 1)
            }

        if !fromBeginning, let resumeEp = libraryViewModel?.resumeShows.first(where: { $0.seriesID == seriesID }) {
            let queue = cached.isEmpty ? [resumeEp] : cached
            return (resumeEp, queue)
        }

        if !cached.isEmpty, let playable = cached.nextPlayableItem(fromBeginning: fromBeginning) {
            return (playable, cached)
        }

        guard let client else { return nil }
        let result = await client.fetchEpisodesOrEmpty(seriesID: seriesID, userID: userID)

        let sorted = result.sorted { a, b in
            let sA = a.parentIndexNumber ?? 1
            let sB = b.parentIndexNumber ?? 1
            if sA != sB { return sA < sB }
            return (a.indexNumber ?? 1) < (b.indexNumber ?? 1)
        }

        guard let playable = sorted.nextPlayableItem(fromBeginning: fromBeginning) else { return nil }
        return (playable, sorted)
    }
}
