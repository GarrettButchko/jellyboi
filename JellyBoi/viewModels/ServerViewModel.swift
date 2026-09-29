//
//  ServerViewModel.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 8/22/26.
//

import Foundation
import Observation
import UIKit
import Get
import JellyfinAPI

private struct StoredSession: Codable {
    let token: String
    let serverURL: URL
    let serverName: String
}

private let sessionKey = "jellyfinSession"

@Observable
@MainActor
class ServerViewModel {

    var serverURL: URL?
    var serverName: String?
    private(set) var client: JellyfinClient?
    var currentUser: UserDto?

    var profileImageURL: URL? {
        guard let client,
              let userID = currentUser?.id,
              currentUser?.primaryImageTag != nil
        else { return nil }
        return client.url(with: Paths.getUserImage(parameters: .init(userID: userID)))
    }

    func setServer(url: URL, name: String) {
        serverURL = url
        serverName = name
        client = JellyfinClient(configuration: .init(
            url: url,
            client: "JellyBoi",
            deviceName: UIDevice.current.name,
            deviceID: UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString,
            version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        ))
    }

    func saveSession(token: String) {
        guard let url = serverURL, let name = serverName else { return }
        KeychainStore.save(StoredSession(token: token, serverURL: url, serverName: name), for: sessionKey)
    }

    /// Restores a previous session from the keychain. Returns `false` if the stored
    /// session is missing or the server rejects the token — caller should sign out.
    func restoreSession() async -> Bool {
        guard let session = KeychainStore.read(StoredSession.self, for: sessionKey) else { return false }

        let restoredClient = JellyfinClient(configuration: .init(
            url: session.serverURL,
            accessToken: session.token,
            client: "JellyBoi",
            deviceName: UIDevice.current.name,
            deviceID: UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString,
            version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        ))

        do {
            let user = try await restoredClient.send(Paths.getCurrentUser).value
            serverURL = session.serverURL
            serverName = session.serverName
            client = restoredClient
            currentUser = user
            return true
        } catch {
            return false
        }
    }

    // MARK: - Progress Management

    func resetProgress(for item: BaseItemDto, onComplete: (@MainActor @Sendable () -> Void)? = nil) async {
        guard let itemID = item.id else { return }
        await resetProgress(forItemID: itemID, onComplete: onComplete)
    }

    func resetProgress(forItemID itemID: String, onComplete: (@MainActor @Sendable () -> Void)? = nil) async {
        if let client {
            _ = try? await client.send(Paths.markUnplayedItem(itemID: itemID, userID: currentUser?.id))
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
            let request = isFavorite
                ? Paths.markFavoriteItem(itemID: itemID, userID: userID)
                : Paths.unmarkFavoriteItem(itemID: itemID, userID: userID)
            let userData = try await client.send(request).value
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
    static let mediaFavoriteToggled = Notification.Name("mediaFavoriteToggled")
}
