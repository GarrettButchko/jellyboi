import SwiftUI
import BaseColors
import SDWebImageSwiftUI
import JellyfinAPI

struct MediaView: View {
    @Environment(ServerViewModel.self) private var serverViewModel
    @Environment(LibraryViewModel.self) private var libraryViewModel
    @Environment(MediaViewModel.self) private var viewModel
    @State private var scrollOffset: CGFloat = 0
    @State private var headerHeight: CGFloat = 120
    @State private var selectedItem: BaseItemDto?
    @State private var sttButtonHeight: CGFloat = 0
    @Namespace private var zoomTransition

    @Environment(\.horizontalSizeClass) private var sizeClass
    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: sizeClass == .regular ? 160 : 110), spacing: 16)]
    }
    private let topID = "TopID"

    var body: some View {
        @Bindable var viewModel = viewModel
        NavigationStack {
            ScrollViewReader { proxy in
                ZStack(alignment: .top) {
                    ScrollView {
                        Color.clear
                            .frame(height: 0)
                            .id(topID)

                        if viewModel.showFavoritesOnly {
                            favoritesContent
                        } else {
                            regularContent
                        }
                    }
                    .animation(.smooth(duration: 0.35), value: viewModel.currentFavoriteItems.map(\.id))
                    .animation(.smooth(duration: 0.3), value: viewModel.filter)
                    .animation(.smooth(duration: 0.3), value: viewModel.showFavoritesOnly)
                    .contentMargins(.top, headerHeight, for: .scrollContent)
                    .contentMargins(.bottom, sttButtonHeight, for: .scrollContent)
                    .onScrollGeometryChange(for: CGFloat.self) { geometry in
                        geometry.contentOffset.y + geometry.contentInsets.top
                    } action: { _, newValue in
                        scrollOffset = newValue
                    }
                    .refreshable {
                        if let client = serverViewModel.client {
                            await viewModel.refresh(using: client)
                        }
                    }

                    // Fixed top header overlay
                    TabPageHeader(
                        title: viewModel.showFavoritesOnly ? "Favorites" : "Library",
                        scrollOffset: scrollOffset,
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
                                    viewModel.showFavoritesOnly.toggle()
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
                        }
                        .padding(.horizontal, 16)
                    }
                    .onChange(of: viewModel.filter) { _, _ in
                        proxy.scrollTo(topID, anchor: .top)
                    }
                    .onChange(of: viewModel.showFavoritesOnly) { _, _ in
                        proxy.scrollTo(topID, anchor: .top)
                    }

                    ScrollToTopOverlay(scrollOffset: scrollOffset, STTButtonHeight: $sttButtonHeight) {
                        withAnimation { proxy.scrollTo(topID, anchor: .top) }
                    }
                }
            }
            .navigationDestination(item: $selectedItem) { item in
                MediaDetailView(item: item)
                    .navigationTransition(.zoom(sourceID: item, in: zoomTransition))
            }
            .toolbarVisibility(.hidden, for: .navigationBar)
            .background(Color.bg.ignoresSafeArea())
        }
    }

    // MARK: - Favorites Content (Filtered by Movies, TV Shows, Collections)

    @ViewBuilder
    private var favoritesContent: some View {
        if viewModel.isLoading && viewModel.currentFavoriteItems.isEmpty {
            SkeletonMediaGrid()
                .transition(.opacity)
        } else if viewModel.currentFavoriteItems.isEmpty {
            let message: String = {
                switch viewModel.filter {
                case .movies: return "You haven't starred any movies yet."
                case .tvShows: return "You haven't starred any TV shows or episodes yet."
                case .collections: return "You haven't starred any collections yet."
                }
            }()
            EmptyStateView(
                icon: "star",
                title: "No Favorite \(viewModel.filter.title)",
                message: message
            )
        } else {
            switch viewModel.filter {
            case .movies:
                mediaGrid(for: viewModel.favoriteMovies)

            case .collections:
                mediaGrid(for: viewModel.favoriteCollections)

            case .tvShows:
                if !viewModel.favoriteShows.isEmpty && !viewModel.favoriteEpisodes.isEmpty {
                    VStack(alignment: .leading, spacing: 28) {
                        favoriteSection(title: "Shows", items: viewModel.favoriteShows)
                        favoriteSection(title: "Episodes", items: viewModel.favoriteEpisodes)
                    }
                    .padding(.bottom, 8)
                } else if !viewModel.favoriteShows.isEmpty {
                    favoriteSection(title: "Shows", items: viewModel.favoriteShows)
                        .padding(.bottom, 8)
                } else {
                    favoriteSection(title: "Episodes", items: viewModel.favoriteEpisodes)
                        .padding(.bottom, 8)
                }
            }
        }
    }

    // MARK: - Regular Library Content

    @ViewBuilder
    private var regularContent: some View {
        if viewModel.regularItems.isEmpty {
            if viewModel.isLoading {
                SkeletonMediaGrid()
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
                    case .collections: return "square.stack.3d.up"
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
        }
    }

    // MARK: - Reusable Components

    private func mediaGrid(for items: [BaseItemDto]) -> some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(items, id: \.id) { item in
                mediaCard(for: item)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.95)),
                        removal: .opacity.combined(with: .scale(scale: 0.85))
                    ))
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .transition(.opacity)
    }

    private func mediaCard(for item: BaseItemDto) -> some View {
        MediaCard(
            item: item,
            posterURL: serverViewModel.client.flatMap { client in
                posterURL(for: item, client: client)
            },
            namespace: zoomTransition,
            onSelect: {
                selectedItem = item
            },
            imageAspectRatio: item.type == .episode ? (2.0 / 3.0) : nil
        )
    }

    private func posterURL(for item: BaseItemDto, client: JellyfinClient) -> URL? {
        if item.type == .episode {
            return libraryViewModel.seriesPosterURL(for: item, client: client)
                ?? libraryViewModel.posterURL(for: item, client: client)
        }
        return libraryViewModel.posterURL(for: item, client: client)
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
