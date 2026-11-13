//
//  RealtimeService.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 11/13/26.
//

import Foundation
import Observation
import JellyfinAPI
import LoggingKit

/// Owns the app's single Jellyfin WebSocket connection.
///
/// The socket is a push channel: `UserDataChanged` and `LibraryChanged` arrive without any
/// subscription. Views never touch the socket. Decoded user data is handed to `ServerViewModel`,
/// which republishes it through `.mediaUserDataChanged` so every local copy applies the same
/// server snapshot.
@Observable
@MainActor
final class RealtimeService {

    static let shared = RealtimeService()

    /// State of the underlying connection, for status UI.
    enum State: Equatable {
        case idle
        case connecting
        case connected
        case offline
    }

    private(set) var state: State = .idle

    /// Called once a burst of library changes settles.
    @ObservationIgnored
    var onLibraryChanged: (@MainActor () -> Void)?

    @ObservationIgnored
    private var session: JellyfinSocket.Session?

    @ObservationIgnored
    private var eventTask: Task<Void, Never>?

    @ObservationIgnored
    private var libraryRefreshTask: Task<Void, Never>?

    @ObservationIgnored
    private var currentServerURL: URL?

    @ObservationIgnored
    private var currentAccessToken: String?

    private init() {}

    // MARK: - Lifecycle

    /// Starts the socket for `client`.
    ///
    /// Calling this again with the same server and token is a no-op, so it is safe to call from
    /// every session restore or network change.
    func start(client: JellyfinClient, userID: String?) {
        let isSameConnection = session != nil
            && currentServerURL == client.configuration.url
            && currentAccessToken == client.accessToken

        guard !isSameConnection else { return }

        stop()

        guard client.accessToken != nil else { return }

        currentServerURL = client.configuration.url
        currentAccessToken = client.accessToken
        state = .connecting

        let session = client.socket().connect()
        self.session = session

        eventTask = Task { [weak self] in
            do {
                for try await event in session.events {
                    // A stopped session must not write into the next one.
                    guard let self, self.session === session else { return }
                    self.handle(event, userID: userID)
                }
            } catch let error as JellyfinSocket.Session.SocketError {
                AppLogger.warning("Realtime socket ended: \(error)")
            } catch {
                AppLogger.warning("Realtime socket ended: \(error.localizedDescription)")
            }

            guard let self, self.session === session else { return }
            self.session = nil
            self.state = .offline
        }
    }

    /// Closes the socket. Safe to call when already stopped.
    func stop() {
        eventTask?.cancel()
        eventTask = nil
        libraryRefreshTask?.cancel()
        libraryRefreshTask = nil
        session?.disconnect()
        session = nil
        currentServerURL = nil
        currentAccessToken = nil
        state = .idle
    }

    // MARK: - Events

    private func handle(_ event: JellyfinSocket.Session.Event, userID: String?) {
        switch event {
        case .connecting:
            state = .connecting

        case .connected:
            state = .connected
            AppLogger.info("Realtime socket connected")

        case .disconnected:
            state = .offline
            AppLogger.info("Realtime socket disconnected; reconnecting")

        case let .message(message):
            handle(message, userID: userID)
        }
    }

    private func handle(_ message: OutboundWebSocketMessage, userID: String?) {
        switch message {
        case let .userDataChangedMessage(message):
            guard let data = message.data else { return }

            // The server can carry updates for other users; ignore everyone but the signed-in one.
            if let targetUserID = data.userID, let userID, targetUserID != userID { return }

            ServerViewModel.shared.applyUserData(data.userDataList)

        case .libraryChangedMessage:
            scheduleLibraryRefresh()

        default:
            break
        }
    }

    // MARK: - Library refresh

    /// Library scans emit a burst of `LibraryChanged`; refetch once the burst settles.
    private func scheduleLibraryRefresh() {
        libraryRefreshTask?.cancel()
        libraryRefreshTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(1))
            } catch {
                return
            }

            guard let self else { return }
            self.onLibraryChanged?()
        }
    }
}
