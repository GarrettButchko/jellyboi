//
//  ContentView.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 8/19/26.
//

import SwiftUI

struct ContentView: View {

    @EnvironmentObject var viewManager: ViewManager
    @State private var transition: AnyTransition = .identity

    var body: some View {
        ZStack {
            switch viewManager.currentView {
            case .getStarted:
                GetStartedView().transition(transition)
            case .serverSignIn:
                ServerSignInView().transition(transition)
            case .signIn:
                SignInView().transition(transition)
            case .tabs:
                TabsView().transition(transition)
            }
        }
        .animation(.easeInOut, value: viewManager.currentView)
        .onChange(of: viewManager.currentView) { oldValue, newValue in
            if oldValue == .getStarted && newValue == .serverSignIn {
                transition = .asymmetric(insertion: .move(edge: .leading), removal: .move(edge: .trailing))
            } else if oldValue == .serverSignIn && newValue == .getStarted {
                transition = .asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .trailing))
            } else {
                transition = .identity
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(ViewManager())
}
