//
//  ContentView.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 8/19/26.
//

import SwiftUI
import BaseColors

struct ContentView: View {

    @EnvironmentObject var viewManager: ViewManager
    @Environment(ServerViewModel.self) private var serverViewModel

    var body: some View {
        ZStack {
            Group {
                if viewManager.isSignedIn {
                    TabsView()
                } else {
                    GetStartedView()
                }
            }
            .animation(.smooth, value: viewManager.isSignedIn)

            if viewManager.showSignInFlow {
                NavigationStack {
                    LetsConnectView()
                        .navigationDestination(isPresented: $viewManager.showServerSignIn) {
                            ServerSignInView()
                        }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .background(Color.bg)
                .clipShape(RoundedRectangle(cornerRadius: 44, style: .continuous))
                .ignoresSafeArea()
                .zIndex(1)
            }
        }
        .animation(.smooth, value: viewManager.showSignInFlow)
        .task {
            guard viewManager.isSignedIn else { return }
            let ok = await serverViewModel.restoreSession()
            if !ok { viewManager.signOut() }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(ViewManager())
}
