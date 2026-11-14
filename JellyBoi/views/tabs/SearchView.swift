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

// MARK: - Skeleton Default Genres

private let defaultGenre = GenreCount(name: "Action", count: 99)

private let defaultGenres: [GenreCount] = [
    defaultGenre,
    GenreCount(name: "Adventure", count: 99),
    GenreCount(name: "Animation", count: 99),
    GenreCount(name: "Comedy", count: 99),
    GenreCount(name: "Crime", count: 99),
    GenreCount(name: "Documentary", count: 99),
    GenreCount(name: "Drama", count: 99),
    GenreCount(name: "Family", count: 99),
    GenreCount(name: "Fantasy", count: 99),
    GenreCount(name: "Horror", count: 99),
    GenreCount(name: "Mystery", count: 99),
    GenreCount(name: "Sci-Fi", count: 99)
]

// MARK: - SearchView

struct SearchView: View {
    @Environment(ServerViewModel.self) private var serverViewModel
    @Environment(LibraryViewModel.self) private var libraryViewModel
    @Environment(SearchViewModel.self) private var viewModel
    @Namespace private var zoomTransition

    @State private var selectedItem: BaseItemDto?
    @State private var selectedGenre: String?
    @State private var scrollPosition = ScrollPosition()

    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        @Bindable var viewModel = viewModel
        NavigationStack {
            ScrollToTopScrollView(position: $scrollPosition) {
                Group {
                    if viewModel.searchText.isEmpty {
                        genreBrowse
                    } else {
                        searchResults
                    }
                }
                .padding(.top, 12)
                .onChange(of: viewModel.searchText) { _, _ in
                    withAnimation { scrollPosition.scrollToTop() }
                }
            }
            .animation(.smooth(duration: 0.25), value: viewModel.searchText.isEmpty)
            // Detail destination — zoom into a media item
            .navigationDestination(item: $selectedItem) { item in
                MediaDetailView(item: item)
                    .navigationTransition(.zoom(sourceID: item.zoomTransitionID(), in: zoomTransition))
            }
            // Genre destination — push a filtered poster grid
            .navigationDestination(item: $selectedGenre) { genre in
                MediaResultsView(genre: genre, items: viewModel.items(inGenre: genre))
            }
            .onReceive(NotificationCenter.default.publisher(for: .dismissMediaDetailToRoot)) { _ in
                selectedItem = nil
            }
            // Applied inside the NavigationStack so the search-role tab hosts the
            // field in the tab bar (bottom) instead of the navigation bar.
            .searchable(text: $viewModel.searchText)
            .background(Color.bg.ignoresSafeArea())
        }
    }

    // MARK: - Genre browse (empty state)

    private var genreBrowse: some View {
        Group {
            if viewModel.isLoading {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: sizeClass == .regular ? 200 : 160), spacing: 12)],
                    spacing: 12
                ) {
                    ForEach(defaultGenres) { genre in
                        GenreChip(genre: genre) {}
                    }
                }
                .padding(.horizontal, 16)
                .skeleton()
                .transition(.opacity)
            } else if viewModel.genres.isEmpty {
                EmptyStateView(
                    icon: "film.stack",
                    title: "No Media in Library",
                    message: "Add movies or TV shows to your Jellyfin server to search and browse genres."
                )
                .transition(.opacity)
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
                .transition(.opacity)
            }
        }
        .animation(.skeleton, value: viewModel.isLoading)
    }

    // MARK: - Search results (active state)

    private var searchResults: some View {
        Group {
            if viewModel.results.isEmpty {
                EmptyStateView(
                    icon: "magnifyingglass",
                    title: "No Results",
                    message: "No titles found matching \"\(viewModel.searchText)\"."
                )
                .transition(.opacity)
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
