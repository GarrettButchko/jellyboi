//
//  ViewManager.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 8/19/26.
//

import SwiftUI
import JellyfinAPI
internal import Combine

@MainActor
class ViewManager: ObservableObject {

    @Published var isSignedIn: Bool
    @Published var showSignInFlow: Bool = false
    @Published var showServerSignIn: Bool = false
    @Published var selectedMediaItem: BaseItemDto?

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
}
