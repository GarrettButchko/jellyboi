//
//  PlaybackManager.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 10/5/26.
//

import SwiftUI
import Observation
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

        init(item: BaseItemDto, startFromBeginning: Bool = false, localFileURL: URL? = nil) {
            self.id = (item.id ?? UUID().uuidString) + (startFromBeginning ? "-start" : "-resume")
            self.item = item
            self.startFromBeginning = startFromBeginning
            self.localFileURL = localFileURL
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
        libraryViewModel: LibraryViewModel? = nil
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

        activeTask = Task { @MainActor in
            let request = PlaybackRequest(item: item, startFromBeginning: fromBeginning)
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
                            libraryViewModel: resolvedLibrary
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

        activeTask = Task { @MainActor in
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
}
