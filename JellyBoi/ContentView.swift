//
//  ContentView.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 8/19/26.
//

import SwiftUI

struct ContentView: View {

    @EnvironmentObject var viewManager: ViewManager

    var body: some View {
        switch viewManager.currentView {
        case .getStarted:
            GetStartedView()
        case .signIn:
            SignInView()
        case .tabs:
            TabsView()
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(ViewManager())
}
