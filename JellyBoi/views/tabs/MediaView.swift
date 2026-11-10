import SwiftUI
import BaseColors
import SDWebImageSwiftUI
import JellyfinAPI

struct MediaView: View {
    @Environment(ServerViewModel.self) private var serverViewModel
    @Environment(LibraryViewModel.self) private var libraryViewModel
    @Environment(DownloadManager.self) private var downloadManager
    @Environment(MediaViewModel.self) private var viewModel
    @State private var headerHeight: CGFloat = 132
    @State private var selectedItem: BaseItemDto?
    @State private var scrollPosition = ScrollPosition()
    @Namespace private var zoomTransition

    private var pageTitle: String {
        if viewModel.showDownloadsOnly {
            return "Downloads"
        } else if viewModel.showFavoritesOnly {
            return "Favorites"
        } else {
            return "Library"
        }
    }

    @ViewBuilder
    private func topHeaderOverlay(isCollapsed: Bool) -> some View {
        @Bindable var viewModel = viewModel
        TabPageHeader(
            title: pageTitle,
            isCollapsed: isCollapsed,
            headerHeight: $headerHeight
        ) {
            HStack(spacing: 10) {
                Picker("Filter", selection: $viewModel.filter) {
                    ForEach(MediaFilter.allCases, id: \.self) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .padding(6)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 25, style: .continuous))

                Button {
                    withAnimation(.smooth(duration: 0.25)) {
                        viewModel.toggleFavorites()
                    }
                } label: {
                    Image(systemName: viewModel.showFavoritesOnly ? "star.fill" : "star")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(viewModel.showFavoritesOnly ? Color.yellow : Color.mainOpp)
                        .frame(width: 44, height: 44)
                        .glassEffect(.regular.interactive(), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation(.smooth(duration: 0.25)) {
                        viewModel.toggleDownloads()
                    }
                } label: {
                    Image(systemName: viewModel.showDownloadsOnly ? "square.and.arrow.down.fill" : "square.and.arrow.down")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(viewModel.showDownloadsOnly ? Color.appAccent : Color.mainOpp)
                        .frame(width: 44, height: 44)
                        .glassEffect(.regular.interactive(), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
        }
    }

    var body: some View {
        @Bindable var viewModel = viewModel
        NavigationStack {
            ZStack(alignment: .top) {
                Color.bg
                    .ignoresSafeArea()

                ScrollToTopScrollView(
                    position: $scrollPosition,
                    topInset: headerHeight,
                    header: { isCollapsed in
                        topHeaderOverlay(isCollapsed: isCollapsed)
                    }
                ) {
                    Group {
                        if viewModel.showDownloadsOnly {
                            downloadsContent
                        } else if viewModel.showFavoritesOnly {
                            favoritesContent
                        } else {
                            regularContent
                        }
                    }
                    .onChange(of: viewModel.filter) { _, _ in
                        withAnimation { scrollPosition.scrollToTop() }
                    }
                    .onChange(of: viewModel.showFavoritesOnly) { _, _ in
                        withAnimation { scrollPosition.scrollToTop() }
                    }
                    .onChange(of: viewModel.showDownloadsOnly) { _, _ in
                        withAnimation { scrollPosition.scrollToTop() }
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: viewModel.filter)
                .animation(.easeInOut(duration: 0.2), value: viewModel.showFavoritesOnly)
                .animation(.easeInOut(duration: 0.2), value: viewModel.showDownloadsOnly)
                .refreshable {
                    if let client = serverViewModel.client {
                        await viewModel.refresh(using: client)
                    }
                }
            }
            .navigationDestination(item: $selectedItem) { item in
                MediaDetailView(item: item)
                    .navigationTransition(.zoom(sourceID: item.zoomTransitionID(), in: zoomTransition))
            }
            .onReceive(NotificationCenter.default.publisher(for: .dismissMediaDetailToRoot)) { _ in
                selectedItem = nil
            }
            .toolbarVisibility(.hidden, for: .navigationBar)
            .background(Color.bg.ignoresSafeArea())
        }
    }

    // MARK: - Completed Downloads Content

    private var downloadedMovies: [BaseItemDto] {
        downloadManager.downloadedMovies.map { movie in
            if let id = movie.id, let liveItem = libraryViewModel.item(for: id) {
                return liveItem
            }
            return movie
        }
    }

    private var downloadedShows: [BaseItemDto] {
        viewModel.downloadedShows(downloadManager: downloadManager)
    }

    private var downloadedEpisodes: [BaseItemDto] {
        viewModel.downloadedEpisodes(downloadManager: downloadManager).map { episode in
            if let id = episode.id, let liveItem = libraryViewModel.item(for: id) {
                return liveItem
            }
            return episode
        }
    }

    @ViewBuilder
    private var downloadsContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            switch viewModel.filter {
            case .movies:
                if !downloadedMovies.isEmpty {
                    mediaGrid(for: downloadedMovies)
                } else {
                    emptyDownloadsView
                }

            case .tvShows:
                if !downloadedShows.isEmpty && !downloadedEpisodes.isEmpty {
                    VStack(alignment: .leading, spacing: 28) {
                        favoriteSection(title: "Shows", items: downloadedShows)
                        favoriteSection(title: "Episodes", items: downloadedEpisodes)
                    }
                } else if !downloadedShows.isEmpty {
                    favoriteSection(title: "Shows", items: downloadedShows)
                } else if !downloadedEpisodes.isEmpty {
                    favoriteSection(title: "Episodes", items: downloadedEpisodes)
                } else {
                    emptyDownloadsView
                }
            }
        }
        .id(viewModel.filter)
        .transition(.opacity)
    }

    private var emptyDownloadsView: some View {
        EmptyStateView(
            icon: "square.and.arrow.down",
            title: "No Downloads",
            message: "You haven't downloaded any \(viewModel.filter.title.lowercased()) yet."
        )
    }

    // MARK: - Favorites Content (Filtered by Movies, TV Shows)

    @ViewBuilder
    private var favoritesContent: some View {
        if viewModel.isLoading && viewModel.currentFavoriteItems.isEmpty {
            MediaGrid.placeholder(namespace: zoomTransition)
                .transition(.opacity)
        } else if viewModel.currentFavoriteItems.isEmpty {
            let message: String = {
                switch viewModel.filter {
                case .movies: return "You haven't starred any movies yet."
                case .tvShows: return "You haven't starred any TV shows or episodes yet."
                }
            }()
            EmptyStateView(
                icon: "star",
                title: "No Favorite \(viewModel.filter.title)",
                message: message
            )
        } else {
            Group {
                switch viewModel.filter {
                case .movies:
                    mediaGrid(for: viewModel.favoriteMovies)

                case .tvShows:
                    if !viewModel.favoriteShows.isEmpty && !viewModel.favoriteEpisodes.isEmpty {
                        VStack(alignment: .leading, spacing: 28) {
                            favoriteSection(title: "Shows", items: viewModel.favoriteShows)
                            favoriteSection(title: "Episodes", items: viewModel.favoriteEpisodes)
                        }
                    } else if !viewModel.favoriteShows.isEmpty {
                        favoriteSection(title: "Shows", items: viewModel.favoriteShows)
                    } else {
                        favoriteSection(title: "Episodes", items: viewModel.favoriteEpisodes)
                    }
                }
            }
            .id(viewModel.filter)
            .transition(.opacity)
        }
    }

    // MARK: - Regular Library Content

    @ViewBuilder
    private var regularContent: some View {
        if viewModel.regularItems.isEmpty {
            if viewModel.isLoading {
                MediaGrid.placeholder(namespace: zoomTransition)
                    .transition(.opacity)
            } else if let error = viewModel.errorMessage {
                EmptyStateView(
                    icon: "wifi.exclamationmark",
                    title: "Couldn't load library",
                    message: error,
                    buttonTitle: "Try Again"
                ) {
                    Task {
                        if let client = serverViewModel.client {
                            await viewModel.refresh(using: client)
                        }
                    }
                }
            } else {
                let emptyIcon: String = {
                    switch viewModel.filter {
                    case .movies: return "film"
                    case .tvShows: return "tv"
                    }
                }()
                EmptyStateView(
                    icon: emptyIcon,
                    title: "No \(viewModel.filter.title)",
                    message: "Nothing here yet. Pull to refresh or add media to your Jellyfin server.",
                    buttonTitle: "Refresh"
                ) {
                    Task {
                        if let client = serverViewModel.client {
                            await viewModel.refresh(using: client)
                        }
                    }
                }
            }
        } else {
            mediaGrid(for: viewModel.regularItems)
                .id(viewModel.filter)
                .transition(.opacity)
        }
    }

    // MARK: - Reusable Components

    private func mediaGrid(for items: [BaseItemDto]) -> some View {
        MediaGrid(items: items, namespace: zoomTransition) { item in
            selectedItem = item
        }
    }

    private func favoriteSection(title: String, items: [BaseItemDto]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Color.mainOpp)
                .padding(.horizontal, 16)

            mediaGrid(for: items)
        }
    }
}
