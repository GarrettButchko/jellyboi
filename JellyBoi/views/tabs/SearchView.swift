//
//  SearchView.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 8/19/26.
//

import SwiftUI
import BaseColors
import JellyfinAPI
import SDWebImageSwiftUI
import MarqueeText

// MARK: - SearchView

struct SearchView: View {
    @EnvironmentObject private var viewManager: ViewManager
    @Environment(ServerViewModel.self) private var serverViewModel
    @Environment(LibraryViewModel.self) private var libraryViewModel
    @Environment(SearchViewModel.self) private var viewModel
    @Namespace private var zoomTransition

    @State private var selectedItem: BaseItemDto?
    @State private var selectedGenre: String?
    @State private var scrollOffset: CGFloat = 0
    @State private var headerHeight: CGFloat = 120

    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        @Bindable var viewModel = viewModel
        NavigationStack {
            ZStack(alignment: .top) {
                ScrollToTopScrollView(topInset: headerHeight, scrollOffset: $scrollOffset) { proxy in
                    Group {
                        if viewModel.searchText.isEmpty {
                            genreBrowse
                        } else {
                            searchResults
                        }
                    }
                    .onChange(of: viewModel.searchText) { _, _ in
                        withAnimation { proxy.scrollToTop() }
                    }
                    .onChange(of: viewModel.showFavoritesOnly) { _, _ in
                        if scrollOffset > 10 {
                            withAnimation { proxy.scrollToTop() }
                        }
                    }
                }
                .animation(.smooth(duration: 0.25), value: viewModel.searchText.isEmpty)
                .animation(.smooth(duration: 0.25), value: viewModel.showFavoritesOnly)

                // Fixed collapsing header with search field + controls
                TabPageHeader(title: "Search", scrollOffset: scrollOffset, headerHeight: $headerHeight) {
                    GlassEffectContainer(spacing: 12) {
                        HStack(spacing: 10) {
                            searchField

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
                    }
                    .padding(.horizontal, 16)
                }
            }
            // Detail destination — zoom into a media item
            .navigationDestination(item: $selectedItem) { item in
                MediaDetailView(item: item)
                    .navigationTransition(.zoom(sourceID: item, in: zoomTransition))
            }
            .navigationDestination(item: $viewManager.selectedMediaItem) { item in
                MediaDetailView(item: item)
            }
            // Genre destination — push a filtered poster grid
            .navigationDestination(item: $selectedGenre) { genre in
                MediaResultsView(genre: genre, items: viewModel.items(inGenre: genre))
            }
            .onReceive(NotificationCenter.default.publisher(for: .dismissMediaDetailToRoot)) { _ in
                selectedItem = nil
            }
            .toolbarVisibility(.hidden, for: .navigationBar)
            .background(Color.bg.ignoresSafeArea())
        }
    }

    // MARK: - Search field

    private var searchField: some View {
        @Bindable var viewModel = viewModel
        return HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.mainOpp.opacity(0.5))

            TextField("Movies, shows, genres, tags…", text: $viewModel.searchText)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(Color.mainOpp)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)

            if !viewModel.searchText.isEmpty {
                Button {
                    viewModel.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.mainOpp.opacity(0.4))
                }
                .transition(.opacity.combined(with: .scale))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 25, style: .continuous))
        .animation(.smooth(duration: 0.2), value: viewModel.searchText.isEmpty)
    }

    // MARK: - Genre browse (empty state)

    private var genreBrowse: some View {
        Group {
            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
            } else if viewModel.genres.isEmpty {
                if viewModel.showFavoritesOnly {
                    EmptyStateView(
                        icon: "star",
                        title: "No Favorites",
                        message: "You haven't added any favorites yet."
                    )
                    .transition(.opacity)
                } else {
                    EmptyStateView(
                        icon: "film.stack",
                        title: "No Media in Library",
                        message: "Add movies or TV shows to your Jellyfin server to search and browse genres."
                    )
                    .transition(.opacity)
                }
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: sizeClass == .regular ? 200 : 160), spacing: 12)],
                    spacing: 12
                ) {
                    ForEach(viewModel.genres) { genre in
                        GenreChip(genre: genre) {
                            selectedGenre = genre.name
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                .transition(.opacity)
            }
        }
    }

    // MARK: - Search results (active state)

    private var searchResults: some View {
        Group {
            if viewModel.results.isEmpty {
                if viewModel.showFavoritesOnly {
                    EmptyStateView(
                        icon: "star",
                        title: "No Favorite Results",
                        message: "No favorite titles found matching \"\(viewModel.searchText)\"."
                    )
                    .transition(.opacity)
                } else {
                    EmptyStateView(
                        icon: "magnifyingglass",
                        title: "No Results",
                        message: "No titles found matching \"\(viewModel.searchText)\"."
                    )
                    .transition(.opacity)
                }
            } else {
                MediaGrid(items: viewModel.results, namespace: zoomTransition) { item in
                    selectedItem = item
                }
                .transition(.opacity)
            }
        }
    }
}

// MARK: - GenreChip

private struct GenreChip: View {
    let genre: GenreCount
    let onTap: () -> Void

    var body: some View {
        let style = GenreStyle.forGenre(genre.name)
        Button(action: onTap) {
            ZStack(alignment: .bottomLeading) {
                // Large icon in the top right corner
                Image(systemName: style.icon)
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
                    .shadow(color: .black.opacity(0.12), radius: 2, x: 0, y: 1)
                    .padding(.top, 12)
                    .padding(.trailing, 12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

                // Text on the bottom still
                Text(genre.name)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, minHeight: 95)
            .background(style.color.gradient)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    SearchView()
        .environment(SearchViewModel())
        .environment(ServerViewModel())
        .environment(LibraryViewModel())
}
