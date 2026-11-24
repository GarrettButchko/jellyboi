import SwiftUI
import BaseColors
import SDWebImageSwiftUI
import JellyfinAPI

// MARK: - Skeleton Default Item IDs

private let defaultMediaGridItemIDs: [String] = (0..<12).map { "default-media-\($0)" }

struct MediaView: View {
    @Environment(ServerViewModel.self) private var serverViewModel
    @Environment(LibraryViewModel.self) private var libraryViewModel
    @Environment(MediaTabViewModel.self) private var viewModel
    @State private var selectedItemID: String?
    @State private var scrollPosition = ScrollPosition()
    @State private var isHeaderCollapsed: Bool = false
    @Namespace private var zoomTransition

    // MARK: - Header

    /// Native scope dropdown; its icon mirrors the active scope.
    private var scopeMenuButton: some View {
        Menu {
            Picker("Section", selection: scopeSelection) {
                ForEach(viewModel.availableScopes, id: \.self) { scope in
                    Label(scope.title, systemImage: scope.icon)
                        .tag(scope)
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: viewModel.scope.icon)
                    .font(.system(size: 17, weight: .semibold))

                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundStyle(Color.mainOpp)
        }
        .accessibilityLabel("Section")
        .accessibilityValue(viewModel.scope.title)
        .accessibilityHint("Opens the section menu")
    }

    /// Writes the native menu selection back into the view model.
    private var scopeSelection: Binding<MediaScope> {
        Binding(
            get: { viewModel.scope },
            set: { scope in
                guard scope != viewModel.scope else { return }
                withAnimation(.smooth(duration: 0.22)) {
                    viewModel.scope = scope
                }
            }
        )
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Color.bg
                    .ignoresSafeArea()

                ScrollToTopScrollView(
                    position: $scrollPosition,
                    isHeaderCollapsed: $isHeaderCollapsed
                ) {
                    VStack(alignment: .leading, spacing: 20) {
                        Text(viewModel.scope.title)
                            .font(.largeTitle.bold())
                            .foregroundStyle(Color.mainOpp)
                            .padding(.horizontal, 16)
                            .padding(.top, 4)
                            .opacity(isHeaderCollapsed ? 0 : 1)
                            .animation(.easeInOut(duration: 0.2), value: isHeaderCollapsed)

                        Group {
                            switch viewModel.scope {
                            case .movies:
                                libraryContent(
                                    itemIDs: viewModel.regularMovieIDs,
                                    emptyIcon: "film",
                                    emptyTitle: "No Movies"
                                )
                            case .tvShows:
                                libraryContent(
                                    itemIDs: viewModel.regularShowIDs,
                                    emptyIcon: "tv",
                                    emptyTitle: "No TV Shows"
                                )
                            case .favorites:
                                favoritesContent
                            case .downloads:
                                downloadsContent
                            }
                        }
                    }
                    .onChange(of: viewModel.scope) { _, _ in
                        withAnimation { scrollPosition.scrollToTop() }
                    }
                    .onChange(of: viewModel.availableScopes) { _, scopes in
                        // Fall back to Movies if the active scope empties out
                        // (last favorite removed, last download deleted).
                        guard !scopes.contains(viewModel.scope) else { return }
                        withAnimation(.smooth(duration: 0.25)) {
                            viewModel.scope = .movies
                        }
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: viewModel.scope)
                .refreshable {
                    if let client = serverViewModel.client {
                        await viewModel.refresh(using: client)
                    }
                }
            }
            .navigationDestination(item: $selectedItemID) { itemID in
                if let item = libraryViewModel[itemID] {
                    MediaDetailView(item: item)
                        .navigationTransition(.zoom(sourceID: item.zoomTransitionID(), in: zoomTransition))
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .dismissMediaDetailToRoot)) { _ in
                selectedItemID = nil
            }
            .navigationTitle(viewModel.scope.title)
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    scopeMenuButton
                }

                ToolbarItem(placement: .principal) {
                    Text(viewModel.scope.title)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.mainOpp)
                        .opacity(isHeaderCollapsed ? 1 : 0)
                        .animation(.easeInOut(duration: 0.2), value: isHeaderCollapsed)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    ProfileAvatarButton()
                }
                .sharedBackgroundVisibility(.hidden)
            }
            .background(Color.bg.ignoresSafeArea())
        }
    }

    // MARK: - Movies & TV Shows

    @ViewBuilder
    private func libraryContent(
        itemIDs: [String],
        emptyIcon: String,
        emptyTitle: String
    ) -> some View {
        Group {
            if itemIDs.isEmpty {
                if viewModel.isLoading {
                    MediaGrid(itemIDs: defaultMediaGridItemIDs, namespace: zoomTransition)
                        .skeleton()
                        .transition(.opacity)
                } else if let error = viewModel.errorMessage {
                    EmptyStateView(
                        icon: "wifi.exclamationmark",
                        title: "Couldn't load library",
                        message: error,
                        buttonTitle: "Try Again"
                    ) {
                        Task { await refreshLibrary() }
                    }
                } else {
                    EmptyStateView(
                        icon: emptyIcon,
                        title: emptyTitle,
                        message: "Nothing here yet. Pull to refresh or add media to your Jellyfin server.",
                        buttonTitle: "Refresh"
                    ) {
                        Task { await refreshLibrary() }
                    }
                }
            } else {
                mediaGrid(for: itemIDs)
                    .id(viewModel.scope)
                    .transition(.opacity)
            }
        }
        .animation(.skeleton, value: viewModel.isLoading)
    }

    // MARK: - Favorites

    @ViewBuilder
    private var favoritesContent: some View {
        let favoriteSections = viewModel.favoriteSections
        Group {
            if viewModel.isLoading && favoriteSections.isEmpty {
                MediaGrid(itemIDs: defaultMediaGridItemIDs, namespace: zoomTransition)
                    .skeleton()
                    .transition(.opacity)
            } else if favoriteSections.isEmpty {
                EmptyStateView(
                    icon: "star",
                    title: "No Favorites",
                    message: "You haven't starred any movies, shows, or episodes yet."
                )
            } else {
                sectionsView(favoriteSections)
            }
        }
        .animation(.skeleton, value: viewModel.isLoading)
    }

    // MARK: - Downloads

    @ViewBuilder
    private var downloadsContent: some View {
        let downloadSections = viewModel.downloadSections
        if downloadSections.isEmpty {
            EmptyStateView(
                icon: "square.and.arrow.down",
                title: "No Downloads",
                message: "You haven't downloaded any movies, shows, or episodes yet."
            )
        } else {
            sectionsView(downloadSections)
        }
    }

    // MARK: - Reusable Components

    @ViewBuilder
    private func sectionsView(_ sections: [MediaSection]) -> some View {
        VStack(alignment: .leading, spacing: 28) {
            ForEach(sections) { section in
                mediaGrid(for: section.itemIDs, title: section.title)
            }
        }
        .id(viewModel.scope)
        .transition(.opacity)
    }

    private func mediaGrid(for itemIDs: [String], title: String? = nil) -> some View {
        MediaGrid(itemIDs: itemIDs, title: title, namespace: zoomTransition) { itemID in
            selectedItemID = itemID
        }
    }

    private func refreshLibrary() async {
        guard let client = serverViewModel.client else { return }
        await viewModel.refresh(using: client)
    }
}
