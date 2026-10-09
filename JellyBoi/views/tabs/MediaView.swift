import SwiftUI
import BaseColors
import SDWebImageSwiftUI
import JellyfinAPI

struct MediaView: View {
    @Environment(ServerViewModel.self) private var serverViewModel
    @Environment(LibraryViewModel.self) private var libraryViewModel
    @Environment(DownloadManager.self) private var downloadManager
    @Environment(MediaViewModel.self) private var viewModel
    @State private var scrollOffset: CGFloat = 0
    @State private var headerHeight: CGFloat = 120
    @State private var selectedItem: BaseItemDto?
    @State private var sttButtonHeight: CGFloat = 0
    @State private var selectedShowDownloads: ShowDownloadGroup?
    @Namespace private var zoomTransition

    @Environment(\.horizontalSizeClass) private var sizeClass
    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: sizeClass == .regular ? 160 : 110), spacing: 16)]
    }
    private let topID = "TopID"

    var body: some View {
        @Bindable var viewModel = viewModel
        NavigationStack {
            ScrollViewReader { proxy in
                ZStack(alignment: .top) {
                    ScrollView {
                        Color.clear
                            .frame(height: 0)
                            .id(topID)

                        if viewModel.showDownloadsOnly {
                            downloadsContent
                        } else if viewModel.showFavoritesOnly {
                            favoritesContent
                        } else {
                            regularContent
                        }
                    }
                    .animation(.easeInOut(duration: 0.2), value: viewModel.filter)
                    .animation(.easeInOut(duration: 0.2), value: viewModel.showFavoritesOnly)
                    .animation(.easeInOut(duration: 0.2), value: viewModel.showDownloadsOnly)
                    .contentMargins(.top, headerHeight, for: .scrollContent)
                    .contentMargins(.bottom, sttButtonHeight, for: .scrollContent)
                    .scrollEdgeEffectHidden(scrollOffset <= 0, for: .top)
                    .onScrollGeometryChange(for: CGFloat.self) { geometry in
                        geometry.contentOffset.y + geometry.contentInsets.top
                    } action: { _, newValue in
                        scrollOffset = newValue
                    }
                    .refreshable {
                        if let client = serverViewModel.client {
                            await viewModel.refresh(using: client)
                        }
                    }

                    // Fixed top header overlay
                    TabPageHeader(
                        title: {
                            if viewModel.showDownloadsOnly && viewModel.showFavoritesOnly {
                                return "Downloaded Favorites"
                            } else if viewModel.showDownloadsOnly {
                                return "Downloads"
                            } else if viewModel.showFavoritesOnly {
                                return "Favorites"
                            } else {
                                return "Library"
                            }
                        }(),
                        scrollOffset: scrollOffset,
                        headerHeight: $headerHeight
                    ) {
                        HStack(spacing: 10) {
                            Picker("Filter", selection: $viewModel.filter) {
                                ForEach(viewModel.availableFilters, id: \.self) { filter in
                                    Text(filter.title).tag(filter)
                                }
                            }
                            .pickerStyle(.segmented)
                            .padding(6)
                            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 25, style: .continuous))

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

                            Button {
                                withAnimation(.smooth(duration: 0.25)) {
                                    viewModel.showDownloadsOnly.toggle()
                                }
                            } label: {
                                Image(systemName: viewModel.showDownloadsOnly ? "square.and.arrow.down.fill" : "square.and.arrow.down")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(viewModel.showDownloadsOnly ? Color.accentColor : Color.mainOpp)
                                    .frame(width: 44, height: 44)
                                    .glassEffect(.regular.interactive(), in: Circle())
                                    .contentShape(Circle())
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 16)
                    }
                    .onChange(of: viewModel.filter) { _, _ in
                        if scrollOffset > 10 {
                            proxy.scrollTo(topID, anchor: .top)
                        }
                    }
                    .onChange(of: viewModel.showFavoritesOnly) { _, _ in
                        if scrollOffset > 10 {
                            proxy.scrollTo(topID, anchor: .top)
                        }
                    }
                    .onChange(of: viewModel.showDownloadsOnly) { _, _ in
                        if scrollOffset > 10 {
                            proxy.scrollTo(topID, anchor: .top)
                        }
                    }

                    ScrollToTopOverlay(scrollOffset: scrollOffset, STTButtonHeight: $sttButtonHeight) {
                        withAnimation { proxy.scrollTo(topID, anchor: .top) }
                    }
                }
            }
            .navigationDestination(item: $selectedItem) { item in
                MediaDetailView(item: item)
                    .navigationTransition(.zoom(sourceID: item, in: zoomTransition))
            }
            .sheet(item: $selectedShowDownloads) { group in
                ShowDownloadsSheet(seriesID: group.id, seriesName: group.seriesName)
            }
            .onReceive(NotificationCenter.default.publisher(for: .dismissMediaDetailToRoot)) { _ in
                selectedItem = nil
            }
            .toolbarVisibility(.hidden, for: .navigationBar)
            .background(Color.bg.ignoresSafeArea())
        }
    }

    // MARK: - Show Download Group Model

    struct ShowDownloadGroup: Identifiable {
        let id: String
        let seriesName: String
        let activeDownloads: [DownloadItem]
        let completedDownloads: [DownloadItem]

        var totalCount: Int { activeDownloads.count + completedDownloads.count }
        var episodesLeft: Int { activeDownloads.count }
        var overallProgress: Double {
            guard totalCount > 0 else { return 0 }
            let completed = Double(completedDownloads.count)
            let active = activeDownloads.reduce(0.0) { $0 + $1.progress }
            return (completed + active) / Double(totalCount)
        }
    }

    private func showDownloadGroups(from items: [DownloadItem]) -> [ShowDownloadGroup] {
        var showMap: [String: (name: String, active: [DownloadItem])] = [:]
        for item in items {
            guard item.item.type == .episode || item.item.seriesName != nil || item.item.seriesID != nil else { continue }
            let showID = item.item.seriesID ?? item.item.parentBackdropItemID ?? item.item.seriesName ?? item.id
            let showName = item.item.seriesName ?? "Show"
            if showMap[showID] == nil {
                showMap[showID] = (name: showName, active: [item])
            } else {
                showMap[showID]?.active.append(item)
            }
        }

        var result: [ShowDownloadGroup] = []
        for (showID, data) in showMap {
            let completed = downloadManager.completedDownloads.filter {
                $0.item.seriesID == showID || $0.item.parentBackdropItemID == showID || ($0.item.type == .episode && $0.item.seriesName == data.name)
            }
            if data.active.count > 1 || (data.active.count + completed.count) > 1 {
                result.append(ShowDownloadGroup(
                    id: showID,
                    seriesName: data.name,
                    activeDownloads: data.active,
                    completedDownloads: completed
                ))
            }
        }
        return result.sorted { $0.seriesName < $1.seriesName }
    }

    private func standaloneDownloads(from items: [DownloadItem], groupedIDs: Set<String>) -> [DownloadItem] {
        items.filter { item in
            let showID = item.item.seriesID ?? item.item.parentBackdropItemID ?? item.item.seriesName ?? item.id
            return !groupedIDs.contains(showID)
        }
    }

    // MARK: - Downloads Content (Stackable with Favorites)

    private var downloadedMovies: [BaseItemDto] {
        let movies = downloadManager.downloadedMovies
        if viewModel.showFavoritesOnly {
            return movies.filter { $0.userData?.isFavorite == true }
        }
        return movies
    }

    private var downloadedShows: [BaseItemDto] {
        let shows = viewModel.downloadedShows(downloadManager: downloadManager)
        if viewModel.showFavoritesOnly {
            return shows.filter { $0.userData?.isFavorite == true }
        }
        return shows
    }

    private var downloadedEpisodes: [BaseItemDto] {
        let episodes = viewModel.downloadedEpisodes(downloadManager: downloadManager)
        if viewModel.showFavoritesOnly {
            let starredShowIDs = Set(viewModel.favoriteShows.compactMap(\.id))
            return episodes.filter { ep in
                guard ep.userData?.isFavorite == true else { return false }
                let showID = ep.seriesID ?? ep.parentBackdropItemID
                if let showID, starredShowIDs.contains(showID) {
                    return false
                }
                return true
            }
        }
        return episodes
    }

    private var activeDownloadsForCurrentFilter: [DownloadItem] {
        downloadManager.activeDownloads.filter { download in
            switch viewModel.filter {
            case .movies:
                return download.item.type == .movie || (download.item.type != .series && download.item.type != .episode && download.item.type != .boxSet && download.item.seriesName == nil)
            case .tvShows:
                return download.item.type == .series || download.item.type == .episode || download.item.seriesName != nil
            }
        }
    }

    @ViewBuilder
    private var downloadsContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Active downloads section for current filter
            if !activeDownloadsForCurrentFilter.isEmpty {
                activeDownloadsSection
            }

            // Completed downloaded media section strictly for current filter
            switch viewModel.filter {
            case .movies:
                if !downloadedMovies.isEmpty {
                    mediaGrid(for: downloadedMovies)
                } else if activeDownloadsForCurrentFilter.isEmpty {
                    emptyDownloadsView
                }

            case .tvShows:
                if !downloadedShows.isEmpty && !downloadedEpisodes.isEmpty {
                    VStack(alignment: .leading, spacing: 28) {
                        favoriteSection(title: "Shows", items: downloadedShows)
                        favoriteSection(title: "Episodes", items: downloadedEpisodes)
                    }
                    .padding(.bottom, 8)
                } else if !downloadedShows.isEmpty {
                    favoriteSection(title: "Shows", items: downloadedShows)
                        .padding(.bottom, 8)
                } else if !downloadedEpisodes.isEmpty {
                    favoriteSection(title: "Episodes", items: downloadedEpisodes)
                        .padding(.bottom, 8)
                } else if activeDownloadsForCurrentFilter.isEmpty {
                    emptyDownloadsView
                }
            }
        }
        .id(viewModel.filter)
        .transition(.opacity)
    }

    @ViewBuilder
    private var activeDownloadsSection: some View {
        let items = activeDownloadsForCurrentFilter
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Downloading")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color.mainOpp)
                    .padding(.horizontal, 16)

                VStack(spacing: 10) {
                    if viewModel.filter == .tvShows {
                        let groups = showDownloadGroups(from: items)
                        ForEach(groups) { group in
                            showDownloadRow(group)
                        }
                        let standaloneItems = standaloneDownloads(from: items, groupedIDs: Set(groups.map(\.id)))
                        ForEach(standaloneItems) { downloadItem in
                            activeDownloadRow(downloadItem)
                        }
                    } else {
                        ForEach(items) { downloadItem in
                            activeDownloadRow(downloadItem)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func showDownloadRow(_ group: ShowDownloadGroup) -> some View {
        Button {
            selectedShowDownloads = group
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "tv")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 6) {
                    Text(group.seriesName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.mainOpp)
                        .lineLimit(1)

                    ProgressView(value: group.overallProgress)
                        .tint(Color.accentColor)

                    HStack {
                        Text("\(group.episodesLeft) \(group.episodesLeft == 1 ? "episode" : "episodes") left")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.mainOpp.opacity(0.6))

                        Spacer()

                        Text("\(Int(group.overallProgress * 100))%")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.mainOpp.opacity(0.8))
                    }
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.mainOpp.opacity(0.5))
                    .padding(.leading, 4)
            }
            .padding(14)
            .background(Color.mainOpp.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func activeDownloadRow(_ downloadItem: DownloadItem) -> some View {
        HStack(spacing: 14) {
            Image(systemName: downloadItem.item.type == .episode ? "tv" : "film")
                .font(.system(size: 22))
                .foregroundStyle(Color.accentColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 6) {
                Text(downloadItem.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.mainOpp)
                    .lineLimit(1)

                ProgressView(value: downloadItem.progress)
                    .tint(Color.accentColor)

                HStack {
                    Text(downloadItem.status == .paused ? "Paused" : downloadItem.formattedProgress)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.mainOpp.opacity(0.6))

                    Spacer()

                    Text(downloadItem.formattedPercentage)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.mainOpp.opacity(0.8))
                }
            }

            HStack(spacing: 8) {
                if downloadItem.status == .downloading {
                    Button {
                        downloadManager.pauseDownload(id: downloadItem.id)
                    } label: {
                        Image(systemName: "pause.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(Color.mainOpp.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                } else if downloadItem.status == .paused {
                    Button {
                        downloadManager.resumeDownload(id: downloadItem.id, client: serverViewModel.client)
                    } label: {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    downloadManager.cancelDownload(id: downloadItem.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.mainOpp.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(Color.mainOpp.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var emptyDownloadsView: some View {
        EmptyStateView(
            icon: "square.and.arrow.down",
            title: viewModel.showFavoritesOnly ? "No Favorite Downloads" : "No Downloads",
            message: viewModel.showFavoritesOnly
                ? "You don't have any starred \(viewModel.filter.title.lowercased()) downloaded."
                : "You haven't downloaded any \(viewModel.filter.title.lowercased()) yet."
        )
    }

    // MARK: - Favorites Content (Filtered by Movies, TV Shows)

    @ViewBuilder
    private var favoritesContent: some View {
        if viewModel.isLoading && viewModel.currentFavoriteItems.isEmpty {
            SkeletonMediaGrid()
                .transition(.opacity)
        } else if viewModel.currentFavoriteItems.isEmpty {
            let message: String = {
                switch viewModel.filter {
                case .movies: return "You haven't starred any movies yet."
                case .tvShows: return "You haven't starred any TV shows or episodes yet."
                }
            }()
            EmptyStateView(
                icon: "star",
                title: "No Favorite \(viewModel.filter.title)",
                message: message
            )
        } else {
            Group {
                switch viewModel.filter {
                case .movies:
                    mediaGrid(for: viewModel.favoriteMovies)

                case .tvShows:
                    if !viewModel.favoriteShows.isEmpty && !viewModel.favoriteEpisodes.isEmpty {
                        VStack(alignment: .leading, spacing: 28) {
                            favoriteSection(title: "Shows", items: viewModel.favoriteShows)
                            favoriteSection(title: "Episodes", items: viewModel.favoriteEpisodes)
                        }
                        .padding(.bottom, 8)
                    } else if !viewModel.favoriteShows.isEmpty {
                        favoriteSection(title: "Shows", items: viewModel.favoriteShows)
                            .padding(.bottom, 8)
                    } else {
                        favoriteSection(title: "Episodes", items: viewModel.favoriteEpisodes)
                            .padding(.bottom, 8)
                    }
                }
            }
            .id(viewModel.filter)
            .transition(.opacity)
        }
    }

    // MARK: - Regular Library Content

    @ViewBuilder
    private var regularContent: some View {
        if viewModel.regularItems.isEmpty {
            if viewModel.isLoading {
                SkeletonMediaGrid()
                    .transition(.opacity)
            } else if let error = viewModel.errorMessage {
                EmptyStateView(
                    icon: "wifi.exclamationmark",
                    title: "Couldn't load library",
                    message: error,
                    buttonTitle: "Try Again"
                ) {
                    Task {
                        if let client = serverViewModel.client {
                            await viewModel.refresh(using: client)
                        }
                    }
                }
            } else {
                let emptyIcon: String = {
                    switch viewModel.filter {
                    case .movies: return "film"
                    case .tvShows: return "tv"
                    }
                }()
                EmptyStateView(
                    icon: emptyIcon,
                    title: "No \(viewModel.filter.title)",
                    message: "Nothing here yet. Pull to refresh or add media to your Jellyfin server.",
                    buttonTitle: "Refresh"
                ) {
                    Task {
                        if let client = serverViewModel.client {
                            await viewModel.refresh(using: client)
                        }
                    }
                }
            }
        } else {
            mediaGrid(for: viewModel.regularItems)
                .id(viewModel.filter)
                .transition(.opacity)
        }
    }

    // MARK: - Reusable Components

    private func mediaGrid(for items: [BaseItemDto]) -> some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(items, id: \.id) { item in
                mediaCard(for: item)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private func mediaCard(for item: BaseItemDto) -> some View {
        MediaCard(
            item: item,
            posterURL: serverViewModel.client.flatMap { client in
                posterURL(for: item, client: client)
            },
            namespace: zoomTransition,
            onSelect: {
                selectedItem = item
            },
            imageAspectRatio: item.type == .episode ? (2.0 / 3.0) : nil
        )
    }

    private func posterURL(for item: BaseItemDto, client: JellyfinClient) -> URL? {
        if item.type == .episode {
            return libraryViewModel.seriesPosterURL(for: item, client: client)
                ?? libraryViewModel.posterURL(for: item, client: client)
        }
        return libraryViewModel.posterURL(for: item, client: client)
    }

    private func favoriteSection(title: String, items: [BaseItemDto]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Color.mainOpp)
                .padding(.horizontal, 16)

            mediaGrid(for: items)
        }
    }
}
