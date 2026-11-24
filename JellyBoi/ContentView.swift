//
//  ContentView.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 8/19/26.
//

import SwiftUI
import BaseColors
import JellyfinAPI
import StatusOverlayKit
import LoggingKit

struct ContentView: View {

    @Environment(ViewManager.self) private var viewManager
    @Environment(ServerViewModel.self) private var serverViewModel
    @Environment(LibraryViewModel.self) private var libraryViewModel
    @Environment(PlaybackManager.self) private var playbackManager
    @Environment(NetworkMonitor.self) private var networkMonitor
    @Environment(\.scenePhase) private var scenePhase

    @State private var isOffline: Bool = false
    @State private var isRestoringSession: Bool = false

    var body: some View {
        @Bindable var bindablePlayback = playbackManager

        ZStack {
            Color.bg
                .ignoresSafeArea()

            Group {
                if !viewManager.isSignedIn {
                    NavigationStack {
                        GetStartedView()
                    }
                    .transition(.opacity)
                } else {
                    ZStack {
                        TabsView()

                        if isOffline {
                            OfflineMediaView(onRetry: {
                                await handleSessionRestore()
                            })
                            .transition(.opacity)
                            .zIndex(1)
                        }
                    }
                    .transition(.opacity)
                }
            }
            .animation(.smooth(duration: 0.35), value: isOffline)
            .animation(.smooth, value: viewManager.isSignedIn)

            #if DEBUG
            if DebugSettings.shared.showFPSCounter {
                FPSOverlayView()
                    .zIndex(999)
            }
            #endif
        }
        .overlay {
            if playbackManager.isPreparing{
                PlaybackLoadingOverlay(
                    message: playbackManager.loadingMessage,
                    onStop: {
                        playbackManager.cancelPreparation()
                    }
                )
            }
        }
        .statusOverlayLoadingIndicator {
            JellyBoiLoadingIndicator()
        }
        .animation(statusOverlaySpring, value: playbackManager.isPreparing)
        .alert(
            playbackManager.currentError?.title ?? "Playback Error",
            item: $bindablePlayback.currentError
        ) { errorInfo in
            Button("Retry") {
                errorInfo.retryAction?()
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
                ZStack(alignment: .topLeading) {
                    NativePlayerView(
                        player: player,
                        onControlsVisibilityChanged: { isVisible in
                            withAnimation(.easeInOut(duration: 0.25)) {
                                playerVM.areControlsVisible = isVisible
                            }
                        },
                        onFirstFrameReady: {
                            playerVM.markFirstFrameRendered()
                        }
                    )
                    .ignoresSafeArea()
                    .statusBarHidden(true)

                    #if DEBUG
                    if DebugSettings.shared.showPlaybackDebugOverlay {
                        Text(playerVM.playbackDiagnosticSummary)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .padding(.top, 50)
                            .padding(.leading, 16)
                            .allowsHitTesting(false)
                    }
                    #endif

                    if playerVM.upNextState.isVisible, let nextItem = playerVM.nextItem {
                        UpNextOverlayView(
                            nextItem: nextItem,
                            state: playerVM.upNextState,
                            areControlsVisible: playerVM.areControlsVisible,
                            onPlayNow: {
                                Task {
                                    await playerVM.playNextItem()
                                }
                            },
                            onDismiss: {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    playerVM.dismissUpNextOverlay()
                                }
                            }
                        )
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.85).combined(with: .opacity),
                            removal: .scale(scale: 0.85).combined(with: .opacity)
                        ))
                        .zIndex(100)
                    }
                }
                .animation(.spring(response: 0.45, dampingFraction: 0.8), value: playerVM.upNextState.isVisible)
                .onAppear {
                    #if os(iOS)
                    OrientationHelper.lockOrientation(.allButUpsideDown)
                    #endif
                    Task {
                        await playerVM.startPlaybackIfNeeded()
                    }
                }
                .onDisappear {
                    #if os(iOS)
                    OrientationHelper.lockOrientation(.portrait, rotateTo: .portrait)
                    #endif
                    playerVM.cleanup()
                }
            }
        }
        .toggleStyle(SwitchToggleStyle(tint: .green))
        .task {
            guard viewManager.isSignedIn else { return }
            await handleSessionRestore()
        }
        .onReceive(NotificationCenter.default.publisher(for: .networkStatusDidChange)) { notification in
            let connected = notification.userInfo?["isConnected"] as? Bool ?? networkMonitor.isConnected
            AppLogger.info("ContentView received networkStatusDidChange: connected=\(connected)")
            if !connected {
                withAnimation(.smooth(duration: 0.35)) {
                    isOffline = true
                }
            } else if viewManager.isSignedIn {
                Task {
                    await handleSessionRestore()
                }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task {
                    let connected = await networkMonitor.checkConnection()
                    if !connected && !isOffline {
                        withAnimation(.smooth(duration: 0.35)) {
                            isOffline = true
                        }
                    }
                }
            }
        }
        .onChange(of: networkMonitor.isConnected) { wasConnected, isConnected in
            if !isConnected {
                withAnimation(.smooth(duration: 0.35)) {
                    isOffline = true
                }
            } else if viewManager.isSignedIn {
                Task {
                    await handleSessionRestore()
                }
            }
        }
        .onChange(of: viewManager.isSignedIn) { _, isSignedIn in
            if !isSignedIn {
                RealtimeService.shared.stop()
            }
        }
    }

    /// Keeps the socket pointed at the current server and refreshes the library after a scan.
    private func startRealtime(client: JellyfinClient, userID: String?) {
        RealtimeService.shared.onLibraryChanged = { [weak libraryViewModel, weak serverViewModel] in
            guard let libraryViewModel,
                  let serverViewModel,
                  let client = serverViewModel.client
            else { return }

            Task {
                await libraryViewModel.refresh(using: client, userID: serverViewModel.currentUser?.id)
            }
        }
        RealtimeService.shared.start(client: client, userID: userID)
    }

    @discardableResult
    private func handleSessionRestore() async -> Bool {
        guard !isRestoringSession else { return !isOffline }
        isRestoringSession = true
        defer { isRestoringSession = false }

        let result = await serverViewModel.restoreSession()
        switch result {
        case .success:
            networkMonitor.setConnected(true)
            if let client = serverViewModel.client {
                let userID = serverViewModel.currentUser?.id
                playbackManager.client = client
                playbackManager.userID = userID
                DownloadManager.shared.client = client
                Task {
                    await libraryViewModel.load(using: client, userID: userID)
                }
                startRealtime(client: client, userID: userID)
            }
            withAnimation(.smooth(duration: 0.35)) {
                isOffline = false
            }
            return true
        case .offline:
            if let client = serverViewModel.client {
                playbackManager.client = client
                DownloadManager.shared.client = client
            }
            withAnimation(.smooth(duration: 0.35)) {
                isOffline = true
            }
            return false
        case .unauthenticated:
            RealtimeService.shared.stop()
            viewManager.signOut()
            return false
        }
    }
}
