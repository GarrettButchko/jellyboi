//
//  HomeView.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 8/19/26.
//

import SwiftUI
import BaseColors
import JellyfinAPI
import SDWebImageSwiftUI

struct HomeView: View {
    @EnvironmentObject var viewManager: ViewManager
    @Environment(ServerViewModel.self) private var serverViewModel
    @Environment(LibraryViewModel.self) private var libraryViewModel
    @Environment(HomeViewModel.self) private var viewModel
    @Namespace private var zoomTransition
    
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    private struct HomeScrollState: Equatable {
        var isPastTop: Bool = false
        var isHeaderCollapsed: Bool = false
        var showScrollToTop: Bool = false
    }

    @State private var scrollState = HomeScrollState()
    @State private var headerHeight: CGFloat = 120
    @State private var heroItem: BaseItemDto?
    @State private var safeAreaTop: CGFloat = 0
    @State private var zoomSourceID: AnyHashable?
    @State private var sttButtonHeight: CGFloat = 0
    @State private var isShowingCollections: Bool = false
    
    private let homeTopID = "homeTop"
    
    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ZStack(alignment: .top) {
                    ScrollView {
                        Color.clear.frame(height: 0).id(homeTopID)
                        LazyVStack(alignment: .leading, spacing: 8) {
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
                            } else if !viewModel.isLoading && viewModel.isLibraryEmpty {
                                EmptyStateView(
                                    icon: "film.stack",
                                    title: "Your library is empty",
                                    message: "Add media to your Jellyfin server to see it here.",
                                    buttonTitle: "Refresh"
                                ) {
                                    Task {
                                        if let client = serverViewModel.client {
                                            await viewModel.refresh(using: client)
                                        }
                                    }
                                }
                            } else {
                                SkeletonZone(showsContent: !viewModel.isLoading) {
                                    SkeletonCarousel()
                                } content: {
                                    if !viewModel.carouselItems.isEmpty {
                                        Carousel(
                                            title: viewModel.topWatchedMovies.isEmpty ? "Featured" : "Continue Watching",
                                            namespace: zoomTransition
                                        ) { item in
                                            guard let client = serverViewModel.client else { return nil }
                                            return libraryViewModel.backdropURL(for: item, client: client)
                                        } onSelect: { item in
                                            zoomSourceID = AnyHashable(item)
                                            viewManager.navigateToMedia(item)
                                        } onSnap: { index, item in
                                            withAnimation(.smooth(duration: 0.4)) { heroItem = item }
                                            if let client = serverViewModel.client {
                                                libraryViewModel.prefetchBackdrops(around: index, items: viewModel.carouselItems, client: client)
                                                libraryViewModel.prefetchPosters(around: index, client: client)
                                            }
                                        }
                                    }
                                }
                                
                                SkeletonZone(showsContent: !viewModel.isLoading) {
                                    SkeletonStatsRow()
                                        .padding(.top, 16)
                                } content: {
                                    if !viewModel.movies.isEmpty {
                                        ScrollView(.horizontal) {
                                            HStack(spacing: 10) {
                                                HomeStatBubble(label: "Movies",   value: viewModel.movies.count,           icon: "film")
                                                HomeStatsDoubleBubble(
                                                    leftLabel: "Shows", leftValue: viewModel.tvSeriesCount, leftIcon: "tv",
                                                    rightLabel: "Episodes", rightValue: viewModel.episodeCount, rightIcon: "film.stack"
                                                )
                                                HomeStatBubble(label: "Watching",  value: viewModel.inProgressMovies.count, icon: "play.circle")
                                                HomeStatBubble(label: "Favorites", value: viewModel.favoritesCount,       icon: "heart.fill")
                                                HomeStatBubble(label: "Completed", value: viewModel.completedCount,       icon: "checkmark.circle.fill")
                                                HomeStatBubble(label: "Hrs Watched", value: viewModel.watchedHours,       icon: "clock.fill")
                                            }
                                            .padding(.horizontal, 16)
                                        }
                                        .scrollIndicators(.hidden)
                                        .padding(.top, 16)
                                    }
                                }
                                
                                ForEach(sectionRows) { config in
                                    SkeletonZone(showsContent: !viewModel.isLoading) {
                                        SkeletonSectionRow()
                                            .padding(.top, 16)
                                    } content: {
                                        if !config.items.isEmpty {
                                            SectionRow(
                                                title: config.title,
                                                items: config.items,
                                                namespace: zoomTransition,
                                                rowKey: config.id,
                                                onTitleTap: config.onTitleTap,
                                                onSelect: { item, zoomID in
                                                    zoomSourceID = zoomID
                                                    viewManager.navigateToMedia(item)
                                                }
                                            ) { item in
                                                guard let client = serverViewModel.client else { return nil }
                                                switch config.posterStyle {
                                                case .poster:       return libraryViewModel.posterURL(for: item, client: client)
                                                case .seriesPoster: return libraryViewModel.seriesPosterURL(for: item, client: client)
                                                }
                                            }
                                            .padding(.top, 16)
                                            .transition(.opacity)
                                        }
                                    }
                                }
                            }
                            
                        }
                        .padding(.bottom, 8)
                        .background(alignment: .top) {
                            if let item = heroItem ?? viewModel.currentCarouselItem,
                               let client = serverViewModel.client {
                                HeroBackdropView(
                                    url: libraryViewModel.backdropURL(for: item, client: client),
                                    itemID: item.id,
                                    blurRadius: 30
                                )
                                .offset(y: -(headerHeight + safeAreaTop + 500))
                                .ignoresSafeArea(edges: .top)
                                .allowsHitTesting(false)
                            }
                        }
                    }
                    .refreshable {
                        if let client = serverViewModel.client {
                            await viewModel.refresh(using: client)
                        }
                    }
                    .navigationDestination(item: $viewManager.selectedMediaItem) { item in
                        MediaDetailView(item: item)
                            .navigationTransition(.zoom(sourceID: zoomSourceID ?? AnyHashable(item), in: zoomTransition))
                    }
                    .navigationDestination(isPresented: $isShowingCollections) {
                        MediaResultsView(collections: viewModel.collections)
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .dismissMediaDetailToRoot)) { _ in
                        isShowingCollections = false
                    }
                    .toolbarVisibility(.hidden, for: .navigationBar)
                    .contentMargins(.top, headerHeight, for: .scrollContent)
                    .contentMargins(.bottom, sttButtonHeight, for: .scrollContent)
                    .scrollEdgeEffectHidden(!scrollState.isPastTop, for: .top)
                    .onScrollGeometryChange(for: HomeScrollState.self) { geometry in
                        let offset = geometry.contentOffset.y + geometry.contentInsets.top
                        return HomeScrollState(
                            isPastTop: offset > 0,
                            isHeaderCollapsed: offset > 40,
                            showScrollToTop: offset > 300
                        )
                    } action: { _, newState in
                        scrollState = newState
                    }
                    
                    
                    TabPageHeader(title: "Home", scrollOffset: scrollState.isHeaderCollapsed ? 100 : 0, headerHeight: $headerHeight, showGradient: horizontalSizeClass != .regular && verticalSizeClass != .compact)
                    
                    ScrollToTopOverlay(scrollOffset: scrollState.showScrollToTop ? 301 : 0, STTButtonHeight: $sttButtonHeight) {
                        withAnimation { proxy.scrollTo(homeTopID, anchor: .top) }
                    }
                }
            } // ScrollViewReader
        }
        .background(Color.bg.ignoresSafeArea())
        .background {
            GeometryReader { geo in
                Color.clear.onAppear { safeAreaTop = geo.safeAreaInsets.top }
            }
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

    private var sectionRows: [HomeSectionConfig] {[
        .init(id: "collections",         title: "Collections",           items: viewModel.collections,         posterStyle: .poster, onTitleTap: { isShowingCollections = true }),
        .init(id: "continueWatching",    title: "Continue Watching",     items: viewModel.inProgressMovies,    posterStyle: .poster),
        .init(id: "continueShows",       title: "Continue Shows",        items: viewModel.resumeShows,          posterStyle: .seriesPoster),
        .init(id: "topRated",            title: "Top Rated",             items: viewModel.recommended,          posterStyle: .poster),
        .init(id: "recentlyAddedMovies", title: "Recently Added Movies", items: viewModel.recentlyAddedMovies, posterStyle: .poster),
        .init(id: "recentlyAddedShows",  title: "Recently Added Shows",  items: viewModel.recentlyAddedShows,  posterStyle: .poster),
    ]}
}



// MARK: - Stat Bubbles

private struct HomeStatBubble: View {
    let label: String
    let value: Int
    let icon: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.mainOpp.opacity(0.45))
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(value)")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.mainOpp)
                Text(label)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.mainOpp.opacity(0.45))
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 56)
        .background(Color.mainOpp.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct HomeStatsDoubleBubble: View {
    let leftLabel: String
    let leftValue: Int
    let leftIcon: String
    let rightLabel: String
    let rightValue: Int
    let rightIcon: String

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: leftIcon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.mainOpp.opacity(0.45))
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(leftValue)")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.mainOpp)
                    Text(leftLabel)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.mainOpp.opacity(0.45))
                }
            }
            .padding(.horizontal, 14)

            Rectangle()
                .fill(Color.mainOpp.opacity(0.15))
                .frame(width: 0.5)
                .padding(.vertical, 14)

            HStack(spacing: 10) {
                Image(systemName: rightIcon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.mainOpp.opacity(0.45))
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(rightValue)")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.mainOpp)
                    Text(rightLabel)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.mainOpp.opacity(0.45))
                }
            }
            .padding(.horizontal, 14)
        }
        .frame(height: 56)
        .background(Color.mainOpp.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}


#Preview {
    HomeView()
        .environment(LibraryViewModel())
}

