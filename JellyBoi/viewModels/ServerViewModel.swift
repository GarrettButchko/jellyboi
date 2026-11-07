//
//  ServerViewModel.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 8/22/26.
//

import Foundation
import Observation
import Get
import JellyfinAPI
import LoggingKit

@Observable
@MainActor
class ServerViewModel {

    var serverURL: URL?
    var serverName: String?
    private(set) var client: JellyfinClient?
    var currentUser: UserDto?

    enum SessionRestoreResult {
        case success
        case offline
        case unauthenticated
    }

    var profileImageURL: URL? {
        guard let client,
              let userID = currentUser?.id,
              currentUser?.primaryImageTag != nil
        else { return nil }
        return client.userImageURL(userID: userID)
    }

    var hasStoredSession: Bool {
        KeychainStore.read(StoredSession.self, for: storedSessionKeychainKey) != nil
    }

    func setServer(url: URL, name: String) {
        serverURL = url
        serverName = name
        client = JellyfinClient(configuration: .init(
            url: url,
            client: "JellyBoi",
            deviceName: PlatformDevice.name,
            deviceID: PlatformDevice.identifier,
            version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        ))
    }

    func saveSession(token: String) {
        guard let url = serverURL, let name = serverName else { return }
        KeychainStore.save(StoredSession(token: token, serverURL: url, serverName: name), for: storedSessionKeychainKey)
    }

    /// Restores a previous session from the keychain.
    /// Returns `.success` if successfully connected to server,
    /// `.offline` if stored session exists but network is offline or server unreachable,
    /// and `.unauthenticated` only if no session exists or server rejected credentials (401).
    @discardableResult
    func restoreSession() async -> SessionRestoreResult {
        guard let session = KeychainStore.read(StoredSession.self, for: storedSessionKeychainKey) else {
            return .unauthenticated
        }

        let restoredClient = JellyfinClient(configuration: .init(
            url: session.serverURL,
            accessToken: session.token,
            client: "JellyBoi",
            deviceName: PlatformDevice.name,
            deviceID: PlatformDevice.identifier,
            version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        ))

        do {
            let user = try await restoredClient.fetchCurrentUser()
            self.serverURL = session.serverURL
            self.serverName = session.serverName
            self.client = restoredClient
            self.currentUser = user
            return .success
        } catch let apiError as APIError {
            self.serverURL = session.serverURL
            self.serverName = session.serverName
            self.client = restoredClient
            if case .unacceptableStatusCode(let code) = apiError, code == 401 {
                AppLogger.warning("Session token rejected by server (401 Unauthorized)", tag: "ServerViewModel")
                return .unauthenticated
            }
            AppLogger.info("Server connection error: \(apiError.localizedDescription), using offline mode", tag: "ServerViewModel")
            return .offline
        } catch {
            self.serverURL = session.serverURL
            self.serverName = session.serverName
            self.client = restoredClient
            AppLogger.info("Network error restoring session (\(error.localizedDescription)), using offline mode", tag: "ServerViewModel")
            return .offline
        }
    }

    // MARK: - Progress Management

    func resetProgress(for item: BaseItemDto, onComplete: (@MainActor @Sendable () -> Void)? = nil) async {
        guard let itemID = item.id else { return }
        await resetProgress(forItemID: itemID, onComplete: onComplete)
    }

    func resetProgress(forItemID itemID: String, onComplete: (@MainActor @Sendable () -> Void)? = nil) async {
        if let client {
            let userID = currentUser?.id
            _ = try? await client.markUnplayed(itemID: itemID, userID: userID)
            try? await client.updatePlaybackProgress(
                itemID: itemID,
                userID: userID,
                isPlayed: false,
                positionTicks: 0,
                playedPercentage: 0
            )
        }

        NotificationCenter.default.post(name: .mediaProgressReset, object: itemID)
        onComplete?()
    }

    // MARK: - Favorite Management

    @discardableResult
    func setFavorite(_ isFavorite: Bool, forItemID itemID: String) async -> UserItemDataDto? {
        guard let client else { return nil }
        let userID = currentUser?.id
        do {
            let userData = try await client.setFavorite(isFavorite, itemID: itemID, userID: userID)
            NotificationCenter.default.post(
                name: .mediaFavoriteToggled,
                object: itemID,
                userInfo: ["isFavorite": isFavorite, "userData": userData]
            )
            return userData
        } catch {
            return nil
        }
    }
}

extension Notification.Name {
    static let mediaProgressReset = Notification.Name("mediaProgressReset")
    static let mediaProgressUpdated = Notification.Name("mediaProgressUpdated")
    static let mediaFavoriteToggled = Notification.Name("mediaFavoriteToggled")
}
