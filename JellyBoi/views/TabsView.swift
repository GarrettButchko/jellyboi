//
//  TabsView.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 8/19/26.
//

import SwiftUI

struct TabsView: View {

    @EnvironmentObject var viewManager: ViewManager
    @Environment(ServerViewModel.self) private var serverViewModel
    @Environment(LibraryViewModel.self) private var libraryViewModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var homeViewModel: HomeViewModel
    @State private var mediaViewModel: MediaViewModel
    @State private var searchViewModel: SearchViewModel

    init() {
        _homeViewModel = State(initialValue: HomeViewModel())
        _mediaViewModel = State(initialValue: MediaViewModel())
        _searchViewModel = State(initialValue: SearchViewModel())
    }

    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("Home", systemImage: "house")
                }

            MediaView()
                .tabItem {
                    Label("Media", systemImage: "rectangle.stack")
                }

            SearchView()
                .tabItem {
                    Label("Search", systemImage: "magnifyingglass")
                }
        }
        .environment(homeViewModel)
        .environment(mediaViewModel)
        .environment(searchViewModel)
        .task {
            if let client = serverViewModel.client {
                await libraryViewModel.load(using: client)
            }
        }
        .onChange(of: serverViewModel.client != nil) { _, hasClient in
            guard hasClient, let client = serverViewModel.client else { return }
            Task { await libraryViewModel.load(using: client) }
        }
        .onAppear {
            homeViewModel.library = libraryViewModel
            mediaViewModel.library = libraryViewModel
            searchViewModel.library = libraryViewModel
        }
    }
}

#Preview {
    TabsView()
        .environmentObject(ViewManager())
        .environment(LibraryViewModel())
        .environment(ServerViewModel())
}
