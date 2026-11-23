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

    static let shared = ServerViewModel()

    /// Convenience global accessor for the current user's ID.
    static var currentUserID: String? {
        shared.currentUser?.id
    }

    var serverURL: URL?
    var serverName: String?
    var serverVersion: String?
    var isConnected: Bool { client != nil }
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

    func signOut() {
        KeychainStore.delete(for: storedSessionKeychainKey)
        KeychainStore.delete(for: "jellyfinSession")
        client = nil
        currentUser = nil
        serverURL = nil
        serverName = nil
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
                AppLogger.warning("Session token rejected by server (401 Unauthorized)")
                return .unauthenticated
            }
            AppLogger.info("Server connection error: \(apiError.localizedDescription), using offline mode")
            return .offline
        } catch {
            self.serverURL = session.serverURL
            self.serverName = session.serverName
            self.client = restoredClient
            AppLogger.info("Network error restoring session (\(error.localizedDescription)), using offline mode")
            return .offline
        }
    }

    // MARK: - Progress Management

    /// Clears watch state for `item` and, for containers, its episodes.
    ///
    /// Nothing is cleared locally before the request. The server's `UserItemDataDto` responses are
    /// broadcast through `.mediaUserDataChanged` and every local copy applies those values, so a
    /// failed request leaves the UI untouched instead of silently disagreeing with the server.
    ///
    /// - Returns: `true` when every request succeeded.
    @discardableResult
    func resetProgress(for item: BaseItemDto, episodes: [BaseItemDto] = []) async -> Bool {
        guard let client, let itemID = item.id else { return false }
        let userID = currentUser?.id

        var targets = [itemID]
        if item.type == .series || item.type == .season {
            // Only episodes that actually carry progress need a request.
            targets += episodes.filter { $0.isWatched || $0.hasProgress }.compactMap(\.id)
        }

        var (dtos, failures) = await Self.markUnplayed(targets, client: client, userID: userID)

        // A container's own user data (`isPlayed`, `unplayedItemCount`) is aggregated from its
        // children, so re-read it once the children have been cleared.
        if targets.count > 1,
           let refreshed = try? await client.fetchItem(itemID: itemID, userID: userID),
           let userData = refreshed.userData {
            dtos.append(userData)
        }

        guard !dtos.isEmpty else { return false }
        broadcastUserData(dtos)
        return failures == 0
    }

    /// Marks items unplayed with bounded concurrency so a long series does not flood the server.
    private static func markUnplayed(
        _ itemIDs: [String],
        client: JellyfinClient,
        userID: String?,
        limit: Int = 4
    ) async -> (dtos: [UserItemDataDto], failures: Int) {
        await withTaskGroup(of: UserItemDataDto?.self) { group in
            var pending = itemIDs[...]

            for _ in 0..<min(limit, itemIDs.count) {
                guard let id = pending.popFirst() else { break }
                group.addTask { try? await client.markUnplayed(itemID: id, userID: userID) }
            }

            var collected: [UserItemDataDto] = []
            while let result = await group.next() {
                if let dto = result { collected.append(dto) }
                if let id = pending.popFirst() {
                    group.addTask { try? await client.markUnplayed(itemID: id, userID: userID) }
                }
            }

            return (collected, itemIDs.count - collected.count)
        }
    }

    // MARK: - Favorite Management

    @discardableResult
    func setFavorite(_ isFavorite: Bool, forItemID itemID: String) async -> UserItemDataDto? {
        guard let client else { return nil }
        let userID = currentUser?.id
        guard let userData = try? await client.setFavorite(isFavorite, itemID: itemID, userID: userID) else {
            return nil
        }
        broadcastUserData([userData])
        return userData
    }

    // MARK: - User Data Broadcasting

    /// Publishes user data pushed by the realtime socket.
    ///
    /// Socket messages carry complete `UserItemDataDto` snapshots, so applying them is the same
    /// operation as a REST response: one broadcast, and every local copy updates.
    func applyUserData(_ dtos: [UserItemDataDto]) {
        broadcastUserData(dtos)
    }

    /// Publishes server-reported user data. This is the single change event every local copy listens to.
    private func broadcastUserData(_ dtos: [UserItemDataDto]) {
        guard !dtos.isEmpty else { return }
        NotificationCenter.default.post(
            name: .mediaUserDataChanged,
            object: nil,
            userInfo: ["userData": dtos]
        )
    }
}

extension Notification.Name {
    /// Server-reported user data changed. `userInfo["userData"]` carries `[UserItemDataDto]`.
    static let mediaUserDataChanged = Notification.Name("mediaUserDataChanged")
    static let mediaProgressUpdated = Notification.Name("mediaProgressUpdated")
}
