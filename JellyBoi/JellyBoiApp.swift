//
//  JellyBoiApp.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 8/19/26.
//

import SwiftUI

@main
struct JellyBoiApp: App {

    @StateObject private var viewManager = ViewManager()
    @State private var serverViewModel = ServerViewModel()
    @State private var libraryViewModel = LibraryViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewManager)
                .environment(serverViewModel)
                .environment(libraryViewModel)
        }
    }
}
