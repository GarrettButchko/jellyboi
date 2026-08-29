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

    @State private var scrollOffset: CGFloat = 0
    @State private var headerHeight: CGFloat = 120
    @State private var heroItem: BaseItemDto?
    @State private var safeAreaTop: CGFloat = 0
    @State private var zoomSourceID: AnyHashable?

    private let homeTopID = "homeTop"

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            ZStack(alignment: .top) {
                ScrollView {
                    Color.clear.frame(height: 0).id(homeTopID)
                    VStack(alignment: .leading) {
                        if let error = viewModel.errorMessage, viewModel.movies.isEmpty {
                            Text(error)
                                .font(.system(.footnote, design: .rounded))
                                .foregroundStyle(Color.mainOpp.opacity(0.6))
                                .padding(.horizontal, 20)
                        } else {
                            SkeletonZone(showsContent: !viewModel.isLoading) {
                                SkeletonCarousel()
                            } content: {
                                Carousel(
                                    title: "Movies",
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
                                        libraryViewModel.prefetchBackdrops(around: index, client: client)
                                        libraryViewModel.prefetchPosters(around: index, client: client)
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
                                                leftLabel: "Shows",    leftValue: viewModel.tvSeriesCount, leftIcon: "tv",
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

                            SkeletonZone(showsContent: !viewModel.isLoading) {
                                SkeletonSectionRow()
                                    .padding(.top, 20)
                            } content: {
                                if !viewModel.inProgressMovies.isEmpty {
                                    HomeSectionRow(
                                        title: "Continue Watching",
                                        items: viewModel.inProgressMovies,
                                        namespace: zoomTransition,
                                        rowKey: "continueWatching",
                                        onSelect: { item, zoomID in
                                            zoomSourceID = zoomID
                                            viewManager.navigateToMedia(item)
                                        }
                                    ) { item in
                                        guard let client = serverViewModel.client else { return nil }
                                        return libraryViewModel.posterURL(for: item, client: client)
                                    }
                                    .padding(.top, 20)
                                }
                            }

                            SkeletonZone(showsContent: !viewModel.isLoading) {
                                SkeletonSectionRow()
                                    .padding(.top, 20)
                            } content: {
                                if !viewModel.resumeShows.isEmpty {
                                    HomeSectionRow(
                                        title: "Continue Shows",
                                        items: viewModel.resumeShows,
                                        namespace: zoomTransition,
                                        rowKey: "continueShows",
                                        onSelect: { item, zoomID in
                                            zoomSourceID = zoomID
                                            viewManager.navigateToMedia(item)
                                        }
                                    ) { item in
                                        guard let client = serverViewModel.client else { return nil }
                                        return libraryViewModel.seriesPosterURL(for: item, client: client)
                                    }
                                    .padding(.top, 20)
                                }
                            }

                            SkeletonZone(showsContent: !viewModel.isLoading) {
                                SkeletonSectionRow()
                                    .padding(.top, 20)
                            } content: {
                                if !viewModel.recommended.isEmpty {
                                    HomeSectionRow(
                                        title: "Top Rated",
                                        items: viewModel.recommended,
                                        namespace: zoomTransition,
                                        rowKey: "topRated",
                                        onSelect: { item, zoomID in
                                            zoomSourceID = zoomID
                                            viewManager.navigateToMedia(item)
                                        }
                                    ) { item in
                                        guard let client = serverViewModel.client else { return nil }
                                        return libraryViewModel.posterURL(for: item, client: client)
                                    }
                                    .padding(.top, 20)
                                }
                            }

                            SkeletonZone(showsContent: !viewModel.isLoading) {
                                SkeletonSectionRow()
                                    .padding(.top, 20)
                            } content: {
                                if !viewModel.recentlyAdded.isEmpty {
                                    HomeSectionRow(
                                        title: "Recently Added",
                                        items: viewModel.recentlyAdded,
                                        namespace: zoomTransition,
                                        rowKey: "recentlyAdded",
                                        onSelect: { item, zoomID in
                                            zoomSourceID = zoomID
                                            viewManager.navigateToMedia(item)
                                        }
                                    ) { item in
                                        guard let client = serverViewModel.client else { return nil }
                                        return libraryViewModel.posterURL(for: item, client: client)
                                    }
                                    .padding(.top, 20)
                                }
                            }
                        }

                        ScrollToTopButton { withAnimation { proxy.scrollTo(homeTopID, anchor: .top) } }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 8)
                    }
                    .padding(.bottom, 16)
                    .background(alignment: .top) {
                        heroBackdrop
                            .offset(y: -(headerHeight + safeAreaTop + 500))
                            .ignoresSafeArea(edges: .top)
                    }
                }
                .navigationDestination(item: $viewManager.selectedMediaItem) { item in
                    MediaDetailView(item: item)
                        .navigationTransition(.zoom(sourceID: zoomSourceID ?? AnyHashable(item), in: zoomTransition))
                }
                .toolbarVisibility(.hidden, for: .navigationBar)
                .contentMargins(.top, headerHeight, for: .scrollContent)
                .contentMargins(.bottom, 12, for: .scrollContent)
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentOffset.y + geometry.contentInsets.top
                } action: { _, newValue in
                    scrollOffset = newValue
                }


                TabPageHeader(title: "Home", scrollOffset: scrollOffset, headerHeight: $headerHeight, showGradient: horizontalSizeClass != .regular && verticalSizeClass != .compact)
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

    @ViewBuilder
    private var heroBackdrop: some View {
        if let item = heroItem ?? viewModel.movies.first,
           let client = serverViewModel.client,
           let url = verticalSizeClass == .compact
                ? libraryViewModel.backgroundURL(for: item, client: client)
                : libraryViewModel.posterURL(for: item, client: client) {
            WebImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: { Color.clear }
            .frame(maxWidth: .infinity)
            .frame(height: 1150)
            .blur(radius: 30)
            .mask(
                LinearGradient(
                    colors: [.black, .black.opacity(0.5), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .ignoresSafeArea(edges: .top)
            .id(item.id)
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.3), value: item.id)
        }
    }
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

// MARK: - Section Row

private struct HomeSectionRow: View {
    let title: String
    let items: [BaseItemDto]
    let namespace: Namespace.ID
    let rowKey: String
    let onSelect: (BaseItemDto, AnyHashable) -> Void
    let posterURL: (BaseItemDto) -> URL?

    @Environment(\.horizontalSizeClass) private var sizeClass

    private var cardWidth: CGFloat { sizeClass == .regular ? 160 : 110 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Color.mainOpp)
                .padding(.horizontal, 16)

            ScrollView(.horizontal) {
                LazyHStack(spacing: 16) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        let zoomID: AnyHashable = AnyHashable("\(rowKey)-\(index)")
                        MediaCard(
                            item: item,
                            posterURL: posterURL(item),
                            namespace: namespace,
                            zoomID: zoomID
                        ) {
                            onSelect(item, zoomID)
                        }
                        .frame(width: cardWidth)
                    }
                }
                .padding(.horizontal, 16)
                .scrollTargetLayout()
            }
            .contentMargins(.vertical, 12, for: .scrollContent)
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
        }
    }
}

#Preview {
    HomeView()
        .environment(LibraryViewModel())
}
