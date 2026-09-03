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
                    .contentMargins(.bottom, 12, for: .scrollContent)
                    .onScrollGeometryChange(for: CGFloat.self) { geometry in
                        geometry.contentOffset.y + geometry.contentInsets.top
                    } action: { _, newValue in
                        scrollOffset = newValue
                    }
                    .animation(.smooth(duration: 0.25), value: viewModel.searchText.isEmpty)
                    .animation(.smooth(duration: 0.25), value: viewModel.sort)

                    // Fixed collapsing header with search field + controls
                    TabPageHeader(title: "Search", scrollOffset: scrollOffset, headerHeight: $headerHeight) {
                        GlassEffectContainer(spacing: 12) {
                            HStack(spacing: 10) {
                                searchField
                                sortButton
                                favoritesButton
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .onChange(of: viewModel.searchText) { _, _ in
                        proxy.scrollTo(topID, anchor: .top)
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

            TextField("Movies, shows, genres…", text: $viewModel.searchText)
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

    // MARK: - Sort button

    private var sortButton: some View {
        @Bindable var viewModel = viewModel
        return Menu {
            ForEach(SearchSort.allCases, id: \.self) { option in
                Button {
                    viewModel.sort = option
                } label: {
                    if viewModel.sort == option {
                        Label(option.title, systemImage: "checkmark")
                    } else {
                        Text(option.title)
                    }
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.mainOpp)
                .frame(width: 44, height: 44)
                .glassEffect(.regular.interactive(), in: Circle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Favorites button

    private var favoritesButton: some View {
        @Bindable var viewModel = viewModel
        return Button {
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
                        GenreChip(
                            genre: genre,
                            posterURL: viewModel.previewItem(forGenre: genre.name).flatMap { item in
                                serverViewModel.client.flatMap { libraryViewModel.backgroundURL(for: item, client: $0) }
                            }
                        ) {
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
                            posterURL: serverViewModel.client.flatMap { libraryViewModel.posterURL(for: item, client: $0) },
                            namespace: zoomTransition
                        ) {
                            selectedItem = item
                        }
                    }
                }
                .id(viewModel.sort)
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
    let posterURL: URL?
    let onTap: () -> Void

    var body: some View {
        let style = GenreStyle.forGenre(genre.name)
        Button(action: onTap) {
            ZStack(alignment: .bottom) {
                // Backdrop image fills the card
                if let url = posterURL {
                    WebImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        style.color.opacity(0.3)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // Gradient rises from the bottom so text stays readable
                    LinearGradient(
                        stops: [
                            .init(color: style.color.opacity(0.97), location: 0),
                            .init(color: style.color.opacity(0.65), location: 0.5),
                            .init(color: style.color.opacity(0.0), location: 1.0),
                        ],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                } else {
                    style.color.opacity(0.25)
                }

                // Genre label spans the full bottom edge
                HStack(spacing: 8) {
                    Image(systemName: style.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)

                    Text(genre.name)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(3)
                        .layoutPriority(1)

                    Text("\(genre.count) title\(genre.count == 1 ? "" : "s")")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.75))
                        .fixedSize()
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, minHeight: 95)
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
                        .id(viewModel.sort)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                        .transition(.opacity)
                    }
                }
                .contentMargins(.top, headerHeight, for: .scrollContent)
                .contentMargins(.bottom, 12, for: .scrollContent)
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentOffset.y + geometry.contentInsets.top
                } action: { _, newValue in
                    scrollOffset = newValue
                }
                .animation(.smooth(duration: 0.25), value: viewModel.sort)

                TabPageHeader(title: genre, scrollOffset: scrollOffset, headerHeight: $headerHeight, showBackButton: true)
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
