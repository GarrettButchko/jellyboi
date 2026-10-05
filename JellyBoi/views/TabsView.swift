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

    init() {
        _homeViewModel = State(initialValue: HomeViewModel())
        _mediaViewModel = State(initialValue: MediaViewModel())
        _searchViewModel = State(initialValue: SearchViewModel())
    }

    var body: some View {
        @Bindable var bindablePlayback = playbackManager

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
                    playbackManager.stop()
                }
            }
        }
        .task {
            playbackManager.client = serverViewModel.client
            playbackManager.userID = serverViewModel.currentUser?.id
            playbackManager.libraryViewModel = libraryViewModel
            if let client = serverViewModel.client {
                await libraryViewModel.load(using: client)
            }
        }
        .onChange(of: serverViewModel.client != nil) { _, hasClient in
            playbackManager.client = serverViewModel.client
            playbackManager.userID = serverViewModel.currentUser?.id
            playbackManager.libraryViewModel = libraryViewModel
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
        .environment(PlaybackManager())
}
