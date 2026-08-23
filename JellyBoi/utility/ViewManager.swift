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

    @Published private(set) var previousView: ViewType = .getStarted
    @Published var currentView: ViewType

    init() {
        if KeychainStore.read(for: "jellyfinSession") != nil {
            self.currentView = .tabs
        } else {
            self.currentView = .getStarted
        }
    }

    func navigateToGetStarted() {
        previousView = currentView
        currentView = .getStarted
    }

    func navigateToServerSignIn() {
        previousView = currentView
        currentView = .serverSignIn
    }

    func navigateToSignIn() {
        previousView = currentView
        currentView = .signIn
    }

    func navigateToTabs() {
        previousView = currentView
        currentView = .tabs
    }

    func signOut() {
        KeychainStore.delete(for: "jellyfinSession")
        previousView = currentView
        currentView = .getStarted
    }
}
