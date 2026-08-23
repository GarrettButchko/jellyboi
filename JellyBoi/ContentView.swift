//
//  ContentView.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 8/19/26.
//

import SwiftUI

struct ContentView: View {

    @EnvironmentObject var viewManager: ViewManager
    @Environment(ServerViewModel.self) private var serverViewModel

    var body: some View {
        ZStack {
            switch viewManager.currentView {
            case .getStarted:
                GetStartedView()
                    .transition(transition(from: viewManager.previousView, to: .getStarted))
            case .serverSignIn:
                ServerSignInView()
                    .transition(transition(from: viewManager.previousView, to: .serverSignIn))
            case .signIn:
                SignInView()
                    .transition(transition(from: viewManager.previousView, to: .signIn))
            case .tabs:
                TabsView()
                    .transition(transition(from: viewManager.previousView, to: .tabs))
            }
        }
        .animation(.smooth, value: viewManager.currentView)
        .task {
            guard viewManager.currentView == .tabs else { return }
            let ok = await serverViewModel.restoreSession()
            if !ok { viewManager.signOut() }
        }
    }

    private func transition(from: ViewType, to: ViewType) -> AnyTransition {
        switch (from, to) {
        case (.getStarted, .serverSignIn):
            return .asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading))
        case (.serverSignIn, .getStarted):
            return .asymmetric(insertion: .move(edge: .leading), removal: .move(edge: .trailing))
        default:
            return .opacity
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(ViewManager())
}
