//
//  OfflineMediaView.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 10/23/26.
//

import SwiftUI
import BaseColors
import SDWebImageSwiftUI
import JellyfinAPI

struct OfflineMediaView: View {
    var onRetry: (() async -> Bool)? = nil

    @Environment(ServerViewModel.self) private var serverViewModel
    @Environment(DownloadManager.self) private var downloadManager
    @Environment(NetworkMonitor.self) private var networkMonitor
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var filter: MediaFilter = .movies
    @State private var scrollOffset: CGFloat = 0
    @State private var headerHeight: CGFloat = 120
    @State private var selectedItem: BaseItemDto?
    @State private var isCheckingConnection: Bool = false
    @State private var checkStatus: CheckStatus = .idle
    @Namespace private var zoomTransition

    private enum CheckStatus {
        case idle
        case stillOffline
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: sizeClass == .regular ? 160 : 110), spacing: 16)]
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Color.bg.ignoresSafeArea()

                ScrollToTopScrollView(topInset: headerHeight, scrollOffset: $scrollOffset) { _ in
                    VStack(alignment: .leading, spacing: 0) {
                        switch filter {
                        case .movies:
                            moviesContent
                        case .tvShows:
                            tvShowsContent
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .animation(.easeInOut(duration: 0.2), value: filter)

                topHeaderOverlay
            }
            .overlay(alignment: .bottom) {
                bottomRetryButton
            }
            .navigationDestination(item: $selectedItem) { item in
                MediaDetailView(item: item)
                    .navigationTransition(.zoom(sourceID: item, in: zoomTransition))
            }
            .onReceive(NotificationCenter.default.publisher(for: .dismissMediaDetailToRoot)) { _ in
                selectedItem = nil
            }
            .toolbarVisibility(.hidden, for: .navigationBar)
            .background(Color.bg.ignoresSafeArea())
            .onReceive(NotificationCenter.default.publisher(for: .networkStatusDidChange)) { notification in
                let connected = notification.userInfo?["isConnected"] as? Bool ?? networkMonitor.isConnected
                if connected && !isCheckingConnection {
                    Task {
                        await performRetry()
                    }
                }
            }
        }
        .background(Color.bg.ignoresSafeArea())
    }

    // MARK: - Header

    private var topHeaderOverlay: some View {
        TabPageHeader(
            title: "Downloads",
            scrollOffset: scrollOffset,
            headerHeight: $headerHeight
        ) {
            Picker("Filter", selection: $filter) {
                ForEach(MediaFilter.allCases, id: \.self) { f in
                    Text(f.title).tag(f)
                }
            }
            .pickerStyle(.segmented)
            .padding(6)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 25, style: .continuous))
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Movies Content

    @ViewBuilder
    private var moviesContent: some View {
        let movies = downloadManager.downloadedMovies
        if movies.isEmpty {
            EmptyStateView(
                icon: "film",
                title: "No Downloaded Movies",
                message: "You haven't downloaded any movies yet. Connect to the internet to download movies for offline viewing."
            )
        } else {
            mediaGrid(for: movies)
                .transition(.opacity)
        }
    }

    // MARK: - TV Shows Content

    @ViewBuilder
    private var tvShowsContent: some View {
        let shows = downloadManager.downloadedShows
        let episodes = downloadManager.downloadedEpisodes
        if shows.isEmpty && episodes.isEmpty {
            EmptyStateView(
                icon: "tv",
                title: "No Downloaded TV Shows",
                message: "You haven't downloaded any TV shows or episodes yet. Connect to the internet to download episodes for offline viewing."
            )
        } else {
            VStack(alignment: .leading, spacing: 24) {
                if !shows.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Shows")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(Color.mainOpp)
                            .padding(.horizontal, 16)

                        mediaGrid(for: shows)
                    }
                }

                if !episodes.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Episodes")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(Color.mainOpp)
                            .padding(.horizontal, 16)

                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(episodes, id: \.id) { episode in
                                MediaCard(
                                    item: episode,
                                    posterURL: posterURL(for: episode),
                                    namespace: zoomTransition,
                                    onSelect: {
                                        selectedItem = episode
                                    },
                                    imageAspectRatio: 2.0 / 3.0
                                )
                            }
                        }
                    }
                }
            }
            .transition(.opacity)
        }
    }

    private func mediaGrid(for items: [BaseItemDto]) -> some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(items, id: \.id) { item in
                MediaCard(
                    item: item,
                    posterURL: posterURL(for: item),
                    namespace: zoomTransition,
                    onSelect: {
                        selectedItem = item
                    },
                    imageAspectRatio: item.type == .episode ? (2.0 / 3.0) : nil
                )
            }
        }
    }

    private func posterURL(for item: BaseItemDto) -> URL? {
        guard let client = serverViewModel.client else { return nil }
        if item.type == .episode {
            return item.seriesPosterURL(client: client)
                ?? item.posterURL(client: client)
        }
        return item.posterURL(client: client)
    }

    // MARK: - Retry Button & Offline Indicator

    private var bottomRetryButton: some View {
        VStack(spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 11, weight: .bold))
                Text("Offline")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(Color.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .glassEffect(.regular, in: Capsule())

            Button {
                Task {
                    await performRetry()
                }
            } label: {
                HStack(spacing: 8) {
                    if isCheckingConnection {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.85)
                    } else {
                        Image(systemName: checkStatus == .stillOffline ? "wifi.exclamationmark" : "arrow.clockwise")
                            .font(.system(size: 14, weight: .bold))
                    }

                    Text(retryButtonTitle)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(Color.white)
                .padding(.horizontal, 22)
                .padding(.vertical, 13)
                .background(
                    Capsule()
                        .fill(Color.accentColor)
                )
            }
            .buttonStyle(.plain)
            .disabled(isCheckingConnection)
        }
        .padding(.bottom, 16)
        .animation(.smooth(duration: 0.25), value: isCheckingConnection)
        .animation(.smooth(duration: 0.25), value: checkStatus)
    }

    private var retryButtonTitle: String {
        if isCheckingConnection {
            return "Checking Connection..."
        } else if checkStatus == .stillOffline {
            return "Still Offline"
        } else {
            return "Retry Connection"
        }
    }

    private func performRetry() async {
        guard !isCheckingConnection else { return }
        withAnimation(.smooth(duration: 0.2)) {
            isCheckingConnection = true
            checkStatus = .idle
        }
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif

        let success = await onRetry?() ?? false

        if success {
            #if os(iOS)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            #endif
            withAnimation(.smooth(duration: 0.2)) {
                checkStatus = .idle
                isCheckingConnection = false
            }
        } else {
            #if os(iOS)
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            #endif
            withAnimation(.smooth(duration: 0.25)) {
                checkStatus = .stillOffline
                isCheckingConnection = false
            }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation(.smooth(duration: 0.25)) {
                checkStatus = .idle
            }
        }
    }
}
