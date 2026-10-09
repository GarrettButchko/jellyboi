//
//  ViewManager.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 8/19/26.
//

import SwiftUI
import JellyfinAPI
internal import Combine

public enum AppTab: Int, Hashable, Sendable {
    case home = 0
    case media = 1
    case search = 2
}

extension Notification.Name {
    static let dismissMediaDetailToRoot = Notification.Name("dismissMediaDetailToRoot")
}

@MainActor
class ViewManager: ObservableObject {

    @Published var isSignedIn: Bool
    @Published var showSignInFlow: Bool = false
    @Published var showServerSignIn: Bool = false
    @Published var selectedMediaItem: BaseItemDto?
    @Published var selectedTab: AppTab = .home

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

    func navigateToMedia(_ item: BaseItemDto) {
        selectedMediaItem = item
    }

    func dismissMedia() {
        selectedMediaItem = nil
    }

    func navigateToDownloads() {
        selectedTab = .media
        dismissToRoot()
    }

    func dismissToRoot() {
        selectedMediaItem = nil
        NotificationCenter.default.post(name: .dismissMediaDetailToRoot, object: nil)
    }
}
