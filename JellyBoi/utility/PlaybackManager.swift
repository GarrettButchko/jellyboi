//
//  PlaybackManager.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 10/5/26.
//

import SwiftUI
import Observation
import Get
import JellyfinAPI
import LoggingKit
import StatusOverlayKit

struct PlaybackErrorInfo: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let retryAction: () -> Void
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

        init(
            item: BaseItemDto,
            startFromBeginning: Bool = false,
            localFileURL: URL? = nil,
            mediaSourceID: String? = nil,
            audioStreamIndex: Int? = nil,
            subtitleStreamIndex: Int? = nil,
            maxBitrate: Int? = nil
        ) {
            self.id = (item.id ?? UUID().uuidString) + (startFromBeginning ? "-start" : "-resume")
            self.item = item
            self.startFromBeginning = startFromBeginning
            self.localFileURL = localFileURL
            self.mediaSourceID = mediaSourceID
            self.audioStreamIndex = audioStreamIndex
            self.subtitleStreamIndex = subtitleStreamIndex
            self.maxBitrate = maxBitrate
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
        mediaSourceID: String? = nil,
        audioStreamIndex: Int? = nil,
        subtitleStreamIndex: Int? = nil,
        maxBitrate: Int? = nil
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
            if targetItem.type == .boxSet {
                if let resolved = await self.resolveFirstItemInCollection(
                    collection: targetItem,
                    client: resolvedClient,
                    userID: resolvedUserID
                ) {
                    targetItem = resolved
                    AppLogger.info("Resolved collection '\(item.name ?? "")' to first item '\(targetItem.name ?? "Unknown")'", tag: "PlaybackManager")
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
                                mediaSourceID: mediaSourceID,
                                audioStreamIndex: audioStreamIndex,
                                subtitleStreamIndex: subtitleStreamIndex,
                                maxBitrate: maxBitrate
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
                    targetItem = resolved
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
                                mediaSourceID: mediaSourceID,
                                audioStreamIndex: audioStreamIndex,
                                subtitleStreamIndex: subtitleStreamIndex,
                                maxBitrate: maxBitrate
                            )
                        }
                    )
                    self.showErrorAlert = true
                    return
                }
            }

            let request = PlaybackRequest(
                item: targetItem,
                startFromBeginning: fromBeginning,
                mediaSourceID: mediaSourceID,
                audioStreamIndex: audioStreamIndex,
                subtitleStreamIndex: subtitleStreamIndex,
                maxBitrate: maxBitrate
            )
            let vm = PlayerViewModel(
                request: request,
                client: resolvedClient,
                userID: resolvedUserID,
                libraryViewModel: resolvedLibrary
            )

            let success = await vm.prepare()
            guard !Task.isCancelled else { return }

            withAnimation(statusOverlaySpring) {
                self.isLoading = false
            }

            if success {
                AppLogger.success("Playback prepared successfully, presenting native player", tag: "PlaybackManager")
                self.activePlayerViewModel = vm
            } else {
                let err = vm.errorMessage ?? "An unknown error occurred while preparing playback."
                AppLogger.error("Playback preparation failed: \(err)", tag: "PlaybackManager")
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
                            mediaSourceID: mediaSourceID,
                            audioStreamIndex: audioStreamIndex,
                            subtitleStreamIndex: subtitleStreamIndex,
                            maxBitrate: maxBitrate
                        )
                    }
                )
                self.showErrorAlert = true
            }
        }
    }

    func playLocal(item: BaseItemDto, fileURL: URL, fromBeginning: Bool = false) {
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
            let request = PlaybackRequest(item: item, startFromBeginning: fromBeginning, localFileURL: fileURL)
            let vm = PlayerViewModel(
                request: request,
                client: self.client,
                userID: self.userID,
                libraryViewModel: self.libraryViewModel
            )

            let success = await vm.prepare()
            guard !Task.isCancelled else { return }

            withAnimation(statusOverlaySpring) {
                self.isLoading = false
            }

            if success {
                self.activePlayerViewModel = vm
            } else {
                let err = vm.errorMessage ?? "An error occurred while opening the local file."
                self.currentError = PlaybackErrorInfo(
                    title: "Playback Error",
                    message: err,
                    retryAction: { [weak self] in
                        self?.playLocal(item: item, fileURL: fileURL, fromBeginning: fromBeginning)
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

    private func resolveFirstItemInCollection(
        collection: BaseItemDto,
        client: JellyfinClient?,
        userID: String?
    ) async -> BaseItemDto? {
        guard let collectionID = collection.id, let client else { return nil }
        var params = Paths.GetItemsParameters()
        params.userID = userID
        params.parentID = collectionID
        params.isRecursive = true
        params.isCollapseBoxSetItems = false
        params.fields = [.primaryImageAspectRatio, .genres, .tags, .overview]
        params.enableUserData = userID != nil
        params.enableImages = true

        let items = (try? await client.send(Paths.getItems(parameters: params)).value.items) ?? []
        let sorted = items.sorted { a, b in
            let dateA = a.premiereDate ?? (a.productionYear.flatMap { Calendar.current.date(from: DateComponents(year: $0)) } ?? .distantPast)
            let dateB = b.premiereDate ?? (b.productionYear.flatMap { Calendar.current.date(from: DateComponents(year: $0)) } ?? .distantPast)
            if dateA != dateB {
                return dateA < dateB
            }
            return (a.sortName ?? a.name ?? "") < (b.sortName ?? b.name ?? "")
        }
        return sorted.first(where: { $0.type == .movie || $0.type == .series || $0.type == .episode }) ?? sorted.first
    }

    private func resolvePlayableEpisode(
        for series: BaseItemDto,
        fromBeginning: Bool,
        client: JellyfinClient?,
        userID: String?,
        libraryViewModel: LibraryViewModel?
    ) async -> BaseItemDto? {
        guard let seriesID = series.id else { return nil }

        if !fromBeginning, let resumeEp = libraryViewModel?.resumeShows.first(where: { $0.seriesID == seriesID }) {
            return resumeEp
        }

        let cached = (libraryViewModel?.episodes ?? [])
            .filter { $0.seriesID == seriesID }
            .sorted { a, b in
                let sA = a.parentIndexNumber ?? 1
                let sB = b.parentIndexNumber ?? 1
                if sA != sB { return sA < sB }
                return (a.indexNumber ?? 1) < (b.indexNumber ?? 1)
            }

        if !cached.isEmpty {
            if !fromBeginning, let unplayed = cached.first(where: { ($0.userData?.isPlayed ?? false) == false }) {
                return unplayed
            }
            return cached.first
        }

        guard let client else { return nil }
        let result = (try? await client.send(
            Paths.getEpisodes(
                seriesID: seriesID,
                parameters: .init(
                    userID: userID,
                    fields: [.primaryImageAspectRatio, .mediaSources, .mediaStreams],
                    enableUserData: true
                )
            )
        ).value.items) ?? []

        let sorted = result.sorted { a, b in
            let sA = a.parentIndexNumber ?? 1
            let sB = b.parentIndexNumber ?? 1
            if sA != sB { return sA < sB }
            return (a.indexNumber ?? 1) < (b.indexNumber ?? 1)
        }

        if !fromBeginning, let unplayed = sorted.first(where: { ($0.userData?.isPlayed ?? false) == false }) {
            return unplayed
        }
        return sorted.first
    }
}
