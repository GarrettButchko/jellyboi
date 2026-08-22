//
//  ViewManager.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 8/19/26.
//

import SwiftUI
internal import Combine

enum ViewType {
    case getStarted
    case serverSignIn
    case signIn
    case tabs
}

@MainActor
class ViewManager: ObservableObject {

    @Published var currentView: ViewType

    init() {
        if KeychainStore.read(for: "jellyfinToken") != nil {
            self.currentView = .tabs
        } else {
            self.currentView = .getStarted
        }
    }

    func navigateToGetStarted() {
        currentView = .getStarted
    }

    func navigateToServerSignIn() {
        currentView = .serverSignIn
    }

    func navigateToSignIn() {
        currentView = .signIn
    }

    func navigateToTabs() {
        currentView = .tabs
    }

    func signOut() {
        KeychainStore.delete(for: "jellyfinToken")
        currentView = .getStarted
    }
}
