//
//  TabsView.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 8/19/26.
//

import SwiftUI
import JellyfinAPI
import StatusOverlayKit

struct TabsView: View {

    @EnvironmentObject var viewManager: ViewManager
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
        @Bindable var bindablePlayback = playbackManager

        TabView(selection: $viewManager.selectedTab) {
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
        .environment(homeViewModel)
        .environment(mediaViewModel)
        .environment(searchViewModel)
        .overlay {
            if playbackManager.isLoading {
                LoadingOverlay(message: playbackManager.loadingMessage)
            }
        }
        .animation(statusOverlaySpring, value: playbackManager.isLoading)
        .alert(
            playbackManager.currentError?.title ?? "Playback Error",
            isPresented: $bindablePlayback.showErrorAlert,
            presenting: playbackManager.currentError
        ) { errorInfo in
            Button("Retry") {
                errorInfo.retryAction()
            }
            .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) {
                playbackManager.clearError()
            }
        } message: { errorInfo in
            Text(errorInfo.message)
        }
        .fullScreenCover(
            item: $bindablePlayback.activePlayerViewModel,
            onDismiss: {
                #if os(iOS)
                OrientationHelper.lockOrientation(.portrait, rotateTo: .portrait)
                #endif
                playbackManager.stop()
            }
        ) { playerVM in
            if let player = playerVM.player {
                NativePlayerView(player: player) {
                    #if os(iOS)
                    OrientationHelper.lockOrientation(.portrait, rotateTo: .portrait)
                    #endif
                    playerVM.cleanup()
                    playbackManager.stop()
                }
                .ignoresSafeArea()
                .statusBarHidden(true)
                .onAppear {
                    #if os(iOS)
                    OrientationHelper.lockOrientation(.allButUpsideDown)
                    #endif
                }
                .onDisappear {
                    #if os(iOS)
                    OrientationHelper.lockOrientation(.portrait, rotateTo: .portrait)
                    #endif
                    playerVM.cleanup()
                }
            }
        }
        .task {
            syncViewModels()
            playbackManager.client = serverViewModel.client
            playbackManager.userID = serverViewModel.currentUser?.id
            playbackManager.libraryViewModel = libraryViewModel
            if let client = serverViewModel.client {
                await libraryViewModel.load(using: client, userID: serverViewModel.currentUser?.id)
            }
        }
        .onAppear {
            syncViewModels()
        }
        .onChange(of: serverViewModel.client != nil) { _, hasClient in
            syncViewModels()
            playbackManager.client = serverViewModel.client
            playbackManager.userID = serverViewModel.currentUser?.id
            if hasClient, let client = serverViewModel.client {
                Task {
                    await libraryViewModel.load(using: client, userID: serverViewModel.currentUser?.id)
                }
            }
        }
    }
}
