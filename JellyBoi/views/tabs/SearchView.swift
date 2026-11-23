import SwiftUI
import BaseColors
import SDWebImageSwiftUI
import JellyfinAPI

// MARK: - Skeleton Default Genres

private let defaultGenres: [GenreCount] = [
    GenreCount(name: "Action", count: 12),
    GenreCount(name: "Comedy", count: 8),
    GenreCount(name: "Drama", count: 15),
    GenreCount(name: "Sci-Fi", count: 6),
    GenreCount(name: "Horror", count: 4),
    GenreCount(name: "Animation", count: 9),
    GenreCount(name: "Thriller", count: 7),
    GenreCount(name: "Romance", count: 5),
    GenreCount(name: "Documentary", count: 3),
    GenreCount(name: "Fantasy", count: 6)
]

struct SearchView: View {
    @Environment(LibraryViewModel.self) private var libraryViewModel
    @Environment(SearchViewModel.self) private var viewModel
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var selectedItemID: String?
    @State private var selectedGenre: String?
    @State private var scrollPosition = ScrollPosition()
    @Namespace private var zoomTransition

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
            .navigationDestination(item: $selectedItemID) { itemID in
                if let item = libraryViewModel.item(for: itemID) {
                    MediaDetailView(item: item)
                        .navigationTransition(.zoom(sourceID: item.zoomTransitionID(), in: zoomTransition))
                }
            }
            .navigationDestination(item: $selectedGenre) { genre in
                MediaResultsView(genre: genre, itemIDs: viewModel.itemIDs(inGenre: genre))
            }
            .onReceive(NotificationCenter.default.publisher(for: .dismissMediaDetailToRoot)) { _ in
                selectedItemID = nil
            }
            .searchable(text: $viewModel.searchText)
            .background(Color.bg.ignoresSafeArea())
        }
    }

    // MARK: - Genre browse (empty state)

    private var genreBrowse: some View {
        Group {
            if viewModel.isLoading && viewModel.genres.isEmpty {
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
            if viewModel.resultIDs.isEmpty {
                EmptyStateView(
                    icon: "magnifyingglass",
                    title: "No Results",
                    message: "No titles found matching \"\(viewModel.searchText)\"."
                )
                .transition(.opacity)
            } else {
                MediaGrid(itemIDs: viewModel.resultIDs, namespace: zoomTransition) { itemID in
                    selectedItemID = itemID
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
                Image(systemName: style.icon)
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
                    .shadow(color: .black.opacity(0.12), radius: 2, x: 0, y: 1)
                    .padding(.top, 12)
                    .padding(.trailing, 12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

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
