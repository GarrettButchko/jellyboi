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
    var heroItemID: String? = nil
}

private let defaultHomeItemIDs: [String] = (0..<8).map { "default-home-\($0)" }

struct HomeView: View {
    @Environment(ServerViewModel.self) private var serverViewModel
    @Environment(LibraryViewModel.self) private var libraryViewModel
    @Environment(HomeTabViewModel.self) private var viewModel
    @Environment(AppPreferences.self) private var preferences
    @Namespace private var zoomTransition
    
    @State private var heroCoordinator = HomeHeroCoordinator()
    @State private var safeAreaTop: CGFloat = 0
    @State private var selectedItemID: String?
    @State private var zoomSourceID: AnyHashable?
    @State private var isShowingCollections: Bool = false
    @State private var selectedStat: HomeStatCategory?
    
    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Color.bg
                    .ignoresSafeArea()

                ScrollToTopScrollView {
                    LazyVStack(alignment: .leading, spacing: 24) {
                            if let error = viewModel.errorMessage, viewModel.movieIDs.isEmpty {
                                EmptyStateView(
                                    icon: "exclamationmark.triangle.fill",
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
                            } else if viewModel.isLoading && viewModel.isLibraryEmpty {
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
                                        itemIDs: defaultHomeItemIDs,
                                        namespace: zoomTransition
                                    )
                                    .skeleton()
                                    .transition(.opacity)
                                }
                            } else {
                                if preferences.showHomeCarousel && !viewModel.carouselItemIDs.isEmpty {
                                    Carousel(
                                        title: viewModel.carouselTitle,
                                        namespace: zoomTransition,
                                        initialIndex: viewModel.carouselSnappedIndex ?? viewModel.carouselItemIDs.count
                                    ) { item in
                                        guard let client = serverViewModel.client else { return nil }
                                        return item.imageWithTitleURL(client: client, seriesLookup: { libraryViewModel.item(for: $0) })
                                            ?? item.backdropURL(client: client)
                                    } onSelect: { itemID in
                                        let item = libraryViewModel.item(for: itemID)
                                        zoomSourceID = item?.zoomTransitionID(isCarousel: true)
                                        selectedItemID = itemID
                                    } onSnap: { index, itemID in
                                        withAnimation(.smooth(duration: 0.4)) {
                                            heroCoordinator.heroItemID = itemID
                                        }
                                        if let client = serverViewModel.client {
                                            libraryViewModel.prefetchBackdrops(around: index, itemIDs: viewModel.carouselItemIDs, client: client)
                                            libraryViewModel.prefetchPosters(around: index, client: client)
                                        }
                                    }
                                    .transition(.opacity)
                                }
                                
                                if !viewModel.movieIDs.isEmpty {
                                    HomeStatsRow(
                                        moviesCount: viewModel.movieIDs.count,
                                        tvSeriesCount: viewModel.tvSeriesCount,
                                        episodeCount: viewModel.episodeCount,
                                        inProgressCount: viewModel.inProgressMovieIDs.count,
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
                                        itemIDs: config.itemIDs,
                                        namespace: zoomTransition,
                                        rowKey: config.id,
                                        onTitleTap: config.onTitleTap,
                                        onSelect: { itemID, zoomID in
                                            zoomSourceID = zoomID
                                            selectedItemID = itemID
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
                                defaultItemID: viewModel.carouselItemIDs.first,
                                client: serverViewModel.client,
                                seriesLookup: { libraryViewModel.item(for: $0) },
                                offsetY: -(safeAreaTop + 500)
                            )
                        }
                }
                .refreshable {
                    if let client = serverViewModel.client {
                        await viewModel.refresh(using: client)
                    }
                }
                .navigationDestination(item: $selectedItemID) { itemID in
                    if let item = libraryViewModel.item(for: itemID) {
                        MediaDetailView(item: item)
                            .navigationTransition(.zoom(sourceID: zoomSourceID ?? item.zoomTransitionID(), in: zoomTransition))
                    }
                }
                .navigationDestination(isPresented: $isShowingCollections) {
                    MediaResultsView(collections: viewModel.collectionIDs)
                }
                .navigationDestination(item: $selectedStat) { stat in
                    statResultsView(for: stat)
                }
                .onReceive(NotificationCenter.default.publisher(for: .dismissMediaDetailToRoot)) { _ in
                    selectedItemID = nil
                    isShowingCollections = false
                    selectedStat = nil
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text("Home")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .fixedSize()
                }
                .sharedBackgroundVisibility(.hidden)
                
                ToolbarItem(placement: .topBarTrailing) {
                    ProfileAvatarButton()
                }
                .sharedBackgroundVisibility(.hidden)
            }
            .background(Color.bg.ignoresSafeArea())
        }
        .background(Color.bg.ignoresSafeArea())
        .background {
            GeometryReader { geo in
                Color.clear.onAppear { safeAreaTop = geo.safeAreaInsets.top }
            }
        }
        .task(id: preferences.showHomeCarousel ? viewModel.carouselItemIDs : []) {
            guard preferences.showHomeCarousel else { return }
            guard let client = serverViewModel.client, !viewModel.carouselItemIDs.isEmpty else { return }
            let transformer = SDImageBlurTransformer(radius: 30)
            let context: [SDWebImageContextOption: Any] = [.imageTransformer: transformer]
            var carouselURLs: [URL] = []
            for itemID in viewModel.carouselItemIDs {
                guard let item = libraryViewModel.item(for: itemID) else { continue }
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
                itemIDs: viewModel.movieIDs,
                emptyIcon: "film",
                emptyTitle: "No Movies",
                emptyMessage: "No movies found in your library."
            )
        case .shows:
            MediaResultsView(
                title: "Shows",
                itemIDs: viewModel.tvShowIDs,
                emptyIcon: "tv",
                emptyTitle: "No TV Shows",
                emptyMessage: "No TV shows found in your library."
            )
        case .episodes:
            MediaResultsView(
                title: "Episodes",
                itemIDs: viewModel.episodeIDs,
                emptyIcon: "film.stack",
                emptyTitle: "No Episodes",
                emptyMessage: "No episodes found in your library."
            )
        case .watching:
            MediaResultsView(
                title: "Watching",
                itemIDs: viewModel.inProgressMovieIDs,
                emptyIcon: "play.circle",
                emptyTitle: "Nothing in Progress",
                emptyMessage: "You don't have any titles currently in progress."
            )
        case .favorites:
            MediaResultsView(
                title: "Favorites",
                itemIDs: viewModel.favoriteIDs,
                emptyIcon: "heart.fill",
                emptyTitle: "No Favorites",
                emptyMessage: "You haven't added any favorites yet."
            )
        case .completed:
            MediaResultsView(
                title: "Completed",
                itemIDs: viewModel.completedMovieIDs,
                emptyIcon: "checkmark.circle.fill",
                emptyTitle: "No Completed Titles",
                emptyMessage: "You haven't finished watching any titles yet."
            )
        case .watchedHours:
            MediaResultsView(
                title: "Watched",
                itemIDs: viewModel.watchedMovieIDs,
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
        let itemIDs: [String]
        let posterStyle: PosterStyle
        var onTitleTap: (() -> Void)? = nil
    }

    private var sectionRows: [HomeSectionConfig] {
        [
            .init(id: "collections",         title: "Collections",           itemIDs: viewModel.collectionIDs,         posterStyle: .poster, onTitleTap: { isShowingCollections = true }),
            .init(id: "continueWatching",    title: "Continue Watching",     itemIDs: viewModel.inProgressMovieIDs,    posterStyle: .poster),
            .init(id: "continueShows",       title: "Continue Shows",        itemIDs: viewModel.resumeShowIDs,          posterStyle: .seriesPoster),
            .init(id: "topRated",            title: "Top Rated",             itemIDs: viewModel.recommendedIDs,          posterStyle: .poster),
            .init(id: "recentlyAddedMovies", title: "Recently Added Movies", itemIDs: viewModel.recentlyAddedMovieIDs, posterStyle: .poster),
            .init(id: "recentlyAddedShows",  title: "Recently Added Shows",  itemIDs: viewModel.recentlyAddedShowIDs,  posterStyle: .poster),
        ].filter { !$0.itemIDs.isEmpty }
    }
}

private struct HomeHeroBackdrop: View {
    let coordinator: HomeHeroCoordinator
    let defaultItemID: String?
    let client: JellyfinClient?
    let seriesLookup: ((String) -> BaseItemDto?)?
    let offsetY: CGFloat

    @Environment(LibraryViewModel.self) private var libraryViewModel

    var body: some View {
        #if DEBUG
        let isCarouselHidden = DebugSettings.shared.hideCarousel || DebugSettings.shared.hideAllHomeRows
        #else
        let isCarouselHidden = false
        #endif

        if !isCarouselHidden,
           AppPreferences.shared.showHomeBlurredBackdrop,
           let activeID = coordinator.heroItemID ?? defaultItemID,
           let activeItem = libraryViewModel.item(for: activeID),
           let url = activeItem.imageWithTitleURL(client: client, seriesLookup: seriesLookup)
            ?? activeItem.backdropURL(client: client) {
            HeroBackdropView(
                url: url,
                itemID: activeID,
                blurRadius: 30
            )
            .offset(y: offsetY)
            .transition(.opacity)
        }
    }
}
