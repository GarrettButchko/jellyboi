//
//  ViewManager.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 8/19/26.
//

import Foundation
import Observation
import JellyfinAPI

public enum AppTab: Int, Hashable, Sendable {
    case home = 0
    case media = 1
    case search = 2
}

extension Notification.Name {
    static let dismissMediaDetailToRoot = Notification.Name("dismissMediaDetailToRoot")
}

@Observable
@MainActor
final class ViewManager {

    static let shared = ViewManager()

    var isSignedIn: Bool
    var selectedTab: AppTab = .home

    init() {
        isSignedIn = KeychainStore.read(for: "jellyfinSession") != nil
            || KeychainStore.read(StoredSession.self, for: storedSessionKeychainKey) != nil
    }

    func completeSignIn() {
        isSignedIn = true
    }

    func signOut() {
        KeychainStore.delete(for: storedSessionKeychainKey)
        KeychainStore.delete(for: "jellyfinSession")
        isSignedIn = false
        selectedTab = .home
        if ServerViewModel.shared.client != nil || ServerViewModel.shared.currentUser != nil {
            ServerViewModel.shared.signOut()
        }
    }

    func navigateToDownloads() {
        selectedTab = .media
        dismissToRoot()
    }

    func dismissToRoot() {
        NotificationCenter.default.post(name: .dismissMediaDetailToRoot, object: nil)
    }
}
