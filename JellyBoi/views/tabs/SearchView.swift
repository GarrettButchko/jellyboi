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
    @Environment(ServerViewModel.self) private var serverViewModel
    @Environment(LibraryViewModel.self) private var libraryViewModel
    @Environment(SearchViewModel.self) private var viewModel
    @Namespace private var zoomTransition

    @State private var selectedItem: BaseItemDto?
    @State private var selectedGenre: String?
    @State private var scrollOffset: CGFloat = 0
    @State private var headerHeight: CGFloat = 120
    @State private var sttButtonHeight: CGFloat = 0

    @Environment(\.horizontalSizeClass) private var sizeClass
    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: sizeClass == .regular ? 160 : 110), spacing: 16)]
    }

    private let topID = "SearchTopID"

    var body: some View {
        @Bindable var viewModel = viewModel
        NavigationStack {
            ScrollViewReader { proxy in
                ZStack(alignment: .top) {
                    ScrollView {
                        Color.clear.frame(height: 0).id(topID)

                        if viewModel.searchText.isEmpty {
                            genreBrowse
                        } else {
                            searchResults
                        }
                    }
                    .contentMargins(.top, headerHeight, for: .scrollContent)
                    .contentMargins(.bottom, sttButtonHeight, for: .scrollContent)
                    .onScrollGeometryChange(for: CGFloat.self) { geometry in
                        geometry.contentOffset.y + geometry.contentInsets.top
                    } action: { _, newValue in
                        scrollOffset = newValue
                    }
                    .animation(.smooth(duration: 0.25), value: viewModel.searchText.isEmpty)

                    // Fixed collapsing header with search field + controls
                    TabPageHeader(title: "Search", scrollOffset: scrollOffset, headerHeight: $headerHeight) {
                        GlassEffectContainer(spacing: 12) {
                            HStack(spacing: 10) {
                                searchField
                                Button {
                                    viewModel.showFavoritesOnly.toggle()
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
                    .onChange(of: viewModel.searchText) { _, _ in
                        proxy.scrollTo(topID, anchor: .top)
                    }

                    ScrollToTopOverlay(scrollOffset: scrollOffset, STTButtonHeight: $sttButtonHeight) {
                        withAnimation { proxy.scrollTo(topID, anchor: .top) }
                    }
                }
            }
            // Detail destination — zoom into a media item
            .navigationDestination(item: $selectedItem) { item in
                MediaDetailView(item: item)
                    .navigationTransition(.zoom(sourceID: item, in: zoomTransition))
            }
            // Genre destination — push a filtered poster grid
            .navigationDestination(item: $selectedGenre) { genre in
                GenreResultsView(genre: genre)
                    .environment(viewModel)
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
                Text("No genres found")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Color.mainOpp.opacity(0.4))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
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
                VStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 32, weight: .medium))
                        .foregroundStyle(Color.mainOpp.opacity(0.25))
                    Text("No results for \"\(viewModel.searchText)\"")
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(Color.mainOpp.opacity(0.4))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 40)
                .padding(.top, 60)
                .transition(.opacity)
            } else {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(viewModel.results, id: \.id) { item in
                        MediaCard(
                            item: item,
                            posterURL: serverViewModel.client.flatMap { c in
                                // Episodes use the parent series poster (2:3 art) so cards
                                // look consistent alongside movies and shows in the grid.
                                item.type == .episode
                                    ? libraryViewModel.seriesPosterURL(for: item, client: c)
                                    : libraryViewModel.posterURL(for: item, client: c)
                            },
                            namespace: zoomTransition,
                            onSelect: {
                                selectedItem = item
                            },
                            imageAspectRatio: item.type == .episode ? (2.0 / 3.0) : nil
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
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

// MARK: - GenreResultsView

struct GenreResultsView: View {
    let genre: String

    @Environment(SearchViewModel.self) private var viewModel
    @Environment(ServerViewModel.self) private var serverViewModel
    @Environment(LibraryViewModel.self) private var libraryViewModel
    @Namespace private var zoomTransition
    @State private var selectedItem: BaseItemDto?
    @State private var scrollOffset: CGFloat = 0
    @State private var headerHeight: CGFloat = 120
    @State private var sttButtonHeight: CGFloat = 0

    @Environment(\.horizontalSizeClass) private var sizeClass
    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: sizeClass == .regular ? 160 : 110), spacing: 16)]
    }

    private let topID = "GenreTopID"

    var body: some View {
        let items = viewModel.items(inGenre: genre)
        ScrollViewReader { proxy in
            ZStack(alignment: .top) {
                ScrollView {
                    Color.clear.frame(height: 0).id(topID)

                    if items.isEmpty {
                        Text("No titles in this genre")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(Color.mainOpp.opacity(0.4))
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    } else {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(items, id: \.id) { item in
                                MediaCard(
                                    item: item,
                                    posterURL: serverViewModel.client.flatMap { libraryViewModel.posterURL(for: item, client: $0) },
                                    namespace: zoomTransition
                                ) {
                                    selectedItem = item
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                        .transition(.opacity)
                    }
                }
                .contentMargins(.top, headerHeight, for: .scrollContent)
                .contentMargins(.bottom, sttButtonHeight, for: .scrollContent)
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentOffset.y + geometry.contentInsets.top
                } action: { _, newValue in
                    scrollOffset = newValue
                }

                TabPageHeader(title: genre, scrollOffset: scrollOffset, headerHeight: $headerHeight, showBackButton: true)

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

#Preview {
    SearchView()
        .environment(SearchViewModel())
        .environment(ServerViewModel())
        .environment(LibraryViewModel())
}
