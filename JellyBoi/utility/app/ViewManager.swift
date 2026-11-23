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
    var showSignInFlow: Bool = false
    var showServerSignIn: Bool = false
    var selectedTab: AppTab = .home

    init() {
        isSignedIn = KeychainStore.read(for: "jellyfinSession") != nil
    }

    func startSignIn() {
        showSignInFlow = true
    }

    func dismissSignInFlow() {
        showSignInFlow = false
    }

    func navigateToServerSignIn() {
        showServerSignIn = true
    }

    func completeSignIn() {
        isSignedIn = true
        showSignInFlow = false
    }

    func signOut() {
        KeychainStore.delete(for: "jellyfinSession")
        isSignedIn = false
        showSignInFlow = false
        showServerSignIn = false
    }

    func navigateToDownloads() {
        selectedTab = .media
        dismissToRoot()
    }

    func dismissToRoot() {
        NotificationCenter.default.post(name: .dismissMediaDetailToRoot, object: nil)
    }
}
