//
//  TabsView.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 8/19/26.
//

import SwiftUI
import JellyfinAPI
import StatusOverlayKit
import BaseColors

struct TabsView: View {

    @Environment(ViewManager.self) private var viewManager
    @Environment(ServerViewModel.self) private var serverViewModel
    @Environment(LibraryViewModel.self) private var libraryViewModel
    @Environment(PlaybackManager.self) private var playbackManager
    @Environment(\.colorScheme) private var colorScheme
    @State private var homeViewModel: HomeViewModel
    @State private var mediaViewModel: MediaViewModel
    @State private var searchViewModel: SearchViewModel

    init(libraryViewModel: LibraryViewModel? = nil) {
        let lib = libraryViewModel ?? LibraryViewModel()
        _homeViewModel = State(initialValue: HomeViewModel(library: lib))
        _mediaViewModel = State(initialValue: MediaViewModel(library: lib))
        _searchViewModel = State(initialValue: SearchViewModel(library: lib))
    }

    private func syncViewModels() {
        if homeViewModel.library !== libraryViewModel {
            homeViewModel.library = libraryViewModel
        }
        if mediaViewModel.library !== libraryViewModel {
            mediaViewModel.library = libraryViewModel
        }
        if searchViewModel.library !== libraryViewModel {
            searchViewModel.library = libraryViewModel
        }
    }

    var body: some View {
        @Bindable var bindableViewManager = viewManager
        TabView(selection: $bindableViewManager.selectedTab) {
            HomeView()
                .tabItem {
                    Label("Home", systemImage: "house")
                }
                .tag(AppTab.home)

            MediaView()
                .tabItem {
                    Label("Media", systemImage: "rectangle.stack")
                }
                .tag(AppTab.media)

            SearchView()
                .tabItem {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .tag(AppTab.search)
        }
        .background(Color.bg.ignoresSafeArea())
        .environment(homeViewModel)
        .environment(mediaViewModel)
        .environment(searchViewModel)
        .task {
            syncViewModels()
            playbackManager.client = serverViewModel.client
            playbackManager.userID = serverViewModel.currentUser?.id
            playbackManager.libraryViewModel = libraryViewModel
            if libraryViewModel.isLibraryEmpty, let client = serverViewModel.client {
                await libraryViewModel.load(using: client, userID: serverViewModel.currentUser?.id)
            }
        }
        .onAppear {
            syncViewModels()
        }
        .onChange(of: serverViewModel.client != nil) { _, _ in
            syncViewModels()
            playbackManager.client = serverViewModel.client
            playbackManager.userID = serverViewModel.currentUser?.id
        }
    }
}
