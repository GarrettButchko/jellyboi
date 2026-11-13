//
//  HomeView.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 8/19/26.
//

import SwiftUI
import BaseColors
import JellyfinAPI
import SDWebImage
import SDWebImageSwiftUI

@Observable
@MainActor
final class HomeHeroCoordinator {
    var heroItem: BaseItemDto? = nil
}

// MARK: - Skeleton Default Items

private let defaultHomeItem = BaseItemDto(
    id: "default-home-item",
    name: "Media Title",
    type: .movie
)

private let defaultHomeItems: [BaseItemDto] = (0..<8).map { index in
    BaseItemDto(
        id: "default-home-\(index)",
        name: defaultHomeItem.name,
        type: defaultHomeItem.type
    )
}

struct HomeView: View {
    @Environment(ServerViewModel.self) private var serverViewModel
    @Environment(LibraryViewModel.self) private var libraryViewModel
    @Environment(HomeViewModel.self) private var viewModel
    @Environment(AppPreferences.self) private var preferences
    @Namespace private var zoomTransition
    
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    @State private var headerHeight: CGFloat = 74
    @State private var heroCoordinator = HomeHeroCoordinator()
    @State private var safeAreaTop: CGFloat = 0
    @State private var selectedItem: BaseItemDto?
    @State private var zoomSourceID: AnyHashable?
    @State private var isShowingCollections: Bool = false
    @State private var selectedStat: HomeStatCategory?
    
    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Color.bg
                    .ignoresSafeArea()

                ScrollToTopScrollView(
                    topInset: headerHeight,
                    header: { isCollapsed in
                        TabPageHeader(
                            title: "Home",
                            isCollapsed: isCollapsed,
                            headerHeight: $headerHeight,
                            showGradient: horizontalSizeClass != .regular && verticalSizeClass != .compact
                        )
                    }
                ) {
                    LazyVStack(alignment: .leading, spacing: 24) {
                            if let error = viewModel.errorMessage, viewModel.movies.isEmpty {
                                EmptyStateView(
                                    icon: "wifi.exclamationmark",
                                    title: "Couldn't load your library",
                                    message: error,
                                    buttonTitle: "Try Again"
                                ) {
                                    Task {
                                        if let client = serverViewModel.client {
                                            await viewModel.refresh(using: client)
                                        }
                                    }
                                }
                            } else if viewModel.isLoading {
                                #if DEBUG
                                let isCarouselHidden = DebugSettings.shared.hideCarousel || DebugSettings.shared.hideAllHomeRows
                                #else
                                let isCarouselHidden = false
                                #endif
                                if preferences.showHomeCarousel && !isCarouselHidden {
                                    Carousel.Placeholder()
                                        .transition(.opacity)
                                }
                                HomeStatsRow.default
                                    .skeleton()
                                    .transition(.opacity)
                                ForEach(0..<3, id: \.self) { _ in
                                    SectionRow(
                                        title: "Movies & Shows",
                                        items: defaultHomeItems,
                                        namespace: zoomTransition
                                    )
                                    .skeleton()
                                    .transition(.opacity)
                                }
                            } else {
                                if preferences.showHomeCarousel && !viewModel.carouselItems.isEmpty {
                                    Carousel(
                                        title: viewModel.carouselTitle,
                                        namespace: zoomTransition,
                                        initialIndex: viewModel.carouselSnappedIndex ?? viewModel.carouselItems.count
                                    ) { item in
                                        guard let client = serverViewModel.client else { return nil }
                                        return item.imageWithTitleURL(client: client, seriesLookup: { libraryViewModel.item(for: $0) })
                                            ?? item.backdropURL(client: client)
                                    } onSelect: { item in
                                        zoomSourceID = AnyHashable(item)
                                        selectedItem = item
                                    } onSnap: { index, item in
                                        withAnimation(.smooth(duration: 0.4)) {
                                            heroCoordinator.heroItem = item
                                        }
                                        if let client = serverViewModel.client {
                                            libraryViewModel.prefetchBackdrops(around: index, items: viewModel.carouselItems, client: client)
                                            libraryViewModel.prefetchPosters(around: index, client: client)
                                        }
                                    }
                                    .transition(.opacity)
                                }
                                
                                if !viewModel.movies.isEmpty {
                                    HomeStatsRow(
                                        moviesCount: viewModel.movies.count,
                                        tvSeriesCount: viewModel.tvSeriesCount,
                                        episodeCount: viewModel.episodeCount,
                                        inProgressCount: viewModel.inProgressMovies.count,
                                        favoritesCount: viewModel.favoritesCount,
                                        completedCount: viewModel.completedCount,
                                        watchedHours: viewModel.watchedHours,
                                        onSelectStat: { stat in
                                            selectedStat = stat
                                        }
                                    )
                                    .transition(.opacity)
                                }
                                
                                ForEach(sectionRows) { config in
                                    SectionRow(
                                        title: config.title,
                                        items: config.items,
                                        namespace: zoomTransition,
                                        rowKey: config.id,
                                        onTitleTap: config.onTitleTap,
                                        onSelect: { item, zoomID in
                                            zoomSourceID = zoomID
                                            selectedItem = item
                                        }
                                    ) { item in
                                        guard let client = serverViewModel.client else { return nil }
                                        switch config.posterStyle {
                                        case .poster:       return item.posterURL(client: client)
                                        case .seriesPoster: return item.seriesPosterURL(client: client)
                                        }
                                    }
                                    .transition(.opacity)
                                }
                            }
                        }
                        .animation(.skeleton, value: viewModel.isLoading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(alignment: .top) {
                            HomeHeroBackdrop(
                                coordinator: heroCoordinator,
                                defaultItem: viewModel.carouselItems.first,
                                client: serverViewModel.client,
                                seriesLookup: { libraryViewModel.item(for: $0) },
                                offsetY: -(headerHeight + safeAreaTop + 500)
                            )
                        }
                }
                .refreshable {
                    if let client = serverViewModel.client {
                        await viewModel.refresh(using: client)
                    }
                }
                .navigationDestination(item: $selectedItem) { item in
                    MediaDetailView(item: item)
                        .navigationTransition(.zoom(sourceID: zoomSourceID ?? AnyHashable(item), in: zoomTransition))
                }
                .navigationDestination(isPresented: $isShowingCollections) {
                    MediaResultsView(collections: viewModel.collections)
                }
                .navigationDestination(item: $selectedStat) { stat in
                    statResultsView(for: stat)
                }
                .onReceive(NotificationCenter.default.publisher(for: .dismissMediaDetailToRoot)) { _ in
                    selectedItem = nil
                    isShowingCollections = false
                    selectedStat = nil
                }
                .toolbarVisibility(.hidden, for: .navigationBar)
            }
            .toolbarVisibility(.hidden, for: .navigationBar)
            .background(Color.bg.ignoresSafeArea())
        }
        .background(Color.bg.ignoresSafeArea())
        .background {
            GeometryReader { geo in
                Color.clear.onAppear { safeAreaTop = geo.safeAreaInsets.top }
            }
        }
        .task(id: preferences.showHomeCarousel ? viewModel.carouselItems.compactMap(\.id) : []) {
            guard preferences.showHomeCarousel else { return }
            guard let client = serverViewModel.client, !viewModel.carouselItems.isEmpty else { return }
            let transformer = SDImageBlurTransformer(radius: 30)
            let context: [SDWebImageContextOption: Any] = [.imageTransformer: transformer]
            var carouselURLs: [URL] = []
            for item in viewModel.carouselItems {
                guard let url = item.imageWithTitleURL(client: client, seriesLookup: { libraryViewModel.item(for: $0) })
                    ?? item.backdropURL(client: client) else { continue }
                carouselURLs.append(url)
                SDWebImageManager.shared.loadImage(
                    with: url,
                    options: [.avoidAutoSetImage, .lowPriority],
                    context: context,
                    progress: nil
                ) { _, _, _, _, _, _ in }
            }
            CarouselImageMemoryCache.shared.preloadImages(for: carouselURLs)
        }
    }

    @ViewBuilder
    private func statResultsView(for stat: HomeStatCategory) -> some View {
        switch stat {
        case .movies:
            MediaResultsView(
                title: "Movies",
                items: viewModel.movies,
                emptyIcon: "film",
                emptyTitle: "No Movies",
                emptyMessage: "No movies found in your library."
            )
        case .shows:
            MediaResultsView(
                title: "Shows",
                items: viewModel.tvShows,
                emptyIcon: "tv",
                emptyTitle: "No TV Shows",
                emptyMessage: "No TV shows found in your library."
            )
        case .episodes:
            MediaResultsView(
                title: "Episodes",
                items: viewModel.episodes,
                emptyIcon: "film.stack",
                emptyTitle: "No Episodes",
                emptyMessage: "No episodes found in your library."
            )
        case .watching:
            MediaResultsView(
                title: "Watching",
                items: viewModel.inProgressMovies,
                emptyIcon: "play.circle",
                emptyTitle: "Nothing in Progress",
                emptyMessage: "You don't have any titles currently in progress."
            )
        case .favorites:
            MediaResultsView(
                title: "Favorites",
                items: viewModel.favorites,
                emptyIcon: "heart.fill",
                emptyTitle: "No Favorites",
                emptyMessage: "You haven't added any favorites yet."
            )
        case .completed:
            MediaResultsView(
                title: "Completed",
                items: viewModel.completedMovies,
                emptyIcon: "checkmark.circle.fill",
                emptyTitle: "No Completed Titles",
                emptyMessage: "You haven't finished watching any titles yet."
            )
        case .watchedHours:
            MediaResultsView(
                title: "Watched",
                items: viewModel.watchedMovies,
                emptyIcon: "clock.fill",
                emptyTitle: "No Watch History",
                emptyMessage: "You haven't watched any titles yet."
            )
        }
    }

    private enum PosterStyle { case poster, seriesPoster }

    private struct HomeSectionConfig: Identifiable {
        let id: String
        let title: String
        let items: [BaseItemDto]
        let posterStyle: PosterStyle
        var onTitleTap: (() -> Void)? = nil
    }

    private var sectionRows: [HomeSectionConfig] {
        [
            .init(id: "collections",         title: "Collections",           items: viewModel.collections,         posterStyle: .poster, onTitleTap: { isShowingCollections = true }),
            .init(id: "continueWatching",    title: "Continue Watching",     items: viewModel.inProgressMovies,    posterStyle: .poster),
            .init(id: "continueShows",       title: "Continue Shows",        items: viewModel.resumeShows,          posterStyle: .seriesPoster),
            .init(id: "topRated",            title: "Top Rated",             items: viewModel.recommended,          posterStyle: .poster),
            .init(id: "recentlyAddedMovies", title: "Recently Added Movies", items: viewModel.recentlyAddedMovies, posterStyle: .poster),
            .init(id: "recentlyAddedShows",  title: "Recently Added Shows",  items: viewModel.recentlyAddedShows,  posterStyle: .poster),
        ].filter { !$0.items.isEmpty }
    }
}

private struct HomeHeroBackdrop: View {
    let coordinator: HomeHeroCoordinator
    let defaultItem: BaseItemDto?
    let client: JellyfinClient?
    let seriesLookup: ((String) -> BaseItemDto?)?
    let offsetY: CGFloat

    var body: some View {
        #if DEBUG
        let isCarouselHidden = DebugSettings.shared.hideCarousel || DebugSettings.shared.hideAllHomeRows
        #else
        let isCarouselHidden = false
        #endif

        if !isCarouselHidden,
           AppPreferences.shared.showHomeBlurredBackdrop,
           AppPreferences.shared.showHomeCarousel,
           let item = coordinator.heroItem ?? defaultItem,
           let client {
            HeroBackdropView(
                url: item.imageWithTitleURL(client: client, seriesLookup: seriesLookup)
                    ?? item.backdropURL(client: client),
                itemID: item.id,
                blurRadius: 30
            )
            .offset(y: offsetY)
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
        }
    }
}
