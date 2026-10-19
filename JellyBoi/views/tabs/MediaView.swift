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
    @State private var selectedShowDownloads: ShowDownloadGroup?
    @State private var itemToCancel: DownloadItem?
    @State private var groupToCancel: ShowDownloadGroup?
    @Namespace private var zoomTransition

    @Environment(\.horizontalSizeClass) private var sizeClass
    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: sizeClass == .regular ? 160 : 110), spacing: 16)]
    }

    var body: some View {
        @Bindable var viewModel = viewModel
        NavigationStack {
            ZStack(alignment: .top) {
                Color.bg
                    .ignoresSafeArea()

                ScrollToTopScrollView(topInset: headerHeight, scrollOffset: $scrollOffset) { proxy in
                    Group {
                        if viewModel.showDownloadsOnly {
                            downloadsContent
                        } else if viewModel.showFavoritesOnly {
                            favoritesContent
                        } else {
                            regularContent
                        }
                    }
                    .onChange(of: viewModel.filter) { _, _ in
                        if scrollOffset > 10 {
                            withAnimation { proxy.scrollToTop() }
                        }
                    }
                    .onChange(of: viewModel.showFavoritesOnly) { _, _ in
                        if scrollOffset > 10 {
                            withAnimation { proxy.scrollToTop() }
                        }
                    }
                    .onChange(of: viewModel.showDownloadsOnly) { _, _ in
                        if scrollOffset > 10 {
                            withAnimation { proxy.scrollToTop() }
                        }
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: viewModel.filter)
                .animation(.easeInOut(duration: 0.2), value: viewModel.showFavoritesOnly)
                .animation(.easeInOut(duration: 0.2), value: viewModel.showDownloadsOnly)
                .refreshable {
                    if let client = serverViewModel.client {
                        await viewModel.refresh(using: client)
                    }
                }

                // Fixed top header overlay
                TabPageHeader(
                    title: {
                        if viewModel.showDownloadsOnly {
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
                                viewModel.toggleFavorites()
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
                                viewModel.toggleDownloads()
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
            }
            .navigationDestination(item: $selectedItem) { item in
                MediaDetailView(item: item)
                    .navigationTransition(.zoom(sourceID: item, in: zoomTransition))
            }
            .sheet(item: $selectedShowDownloads) { group in
                ShowDownloadsSheet(seriesID: group.id, seriesName: group.seriesName)
                    .presentationBackground(Color.bg)
            }
            .alert(
                itemToCancel?.status == .failed ? "Download Failed" : "Cancel Download?",
                isPresented: Binding(
                    get: { itemToCancel != nil },
                    set: { if !$0 { itemToCancel = nil } }
                ),
                presenting: itemToCancel
            ) { item in
                if item.status == .failed {
                    Button("Remove", role: .destructive) {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            downloadManager.cancelDownload(id: item.id)
                        }
                        itemToCancel = nil
                    }
                    Button("Retry") {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            downloadManager.resumeDownload(id: item.id, client: serverViewModel.client)
                        }
                        itemToCancel = nil
                    }
                    Button("Acknowledge", role: .cancel) {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            downloadManager.cancelDownload(id: item.id)
                        }
                        itemToCancel = nil
                    }
                } else {
                    Button("Cancel Download", role: .destructive) {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            downloadManager.cancelDownload(id: item.id)
                        }
                        itemToCancel = nil
                    }
                    Button("Keep", role: .cancel) {
                        itemToCancel = nil
                    }
                }
            } message: { item in
                if item.status == .failed {
                    Text(item.errorMessage ?? "An error occurred during download or transcoding.")
                } else {
                    Text("Are you sure you want to cancel the download for '\(item.title)'?")
                }
            }
            .alert(
                "Cancel Downloads?",
                isPresented: Binding(
                    get: { groupToCancel != nil },
                    set: { if !$0 { groupToCancel = nil } }
                ),
                presenting: groupToCancel
            ) { group in
                Button("Cancel Downloads", role: .destructive) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        downloadManager.cancelDownloads(ids: group.activeDownloads.map(\.id))
                    }
                    groupToCancel = nil
                }
                Button("Keep", role: .cancel) {
                    groupToCancel = nil
                }
            } message: { group in
                Text("Are you sure you want to cancel all downloads for '\(group.seriesName)'?")
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
        var isAllFailed: Bool {
            !activeDownloads.isEmpty && activeDownloads.allSatisfy { $0.status == .failed }
        }
        var representativeItem: BaseItemDto? {
            activeDownloads.first?.item ?? completedDownloads.first?.item
        }
        var formattedTimeRemaining: String? {
            guard !isAllFailed else { return nil }
            if let activeItem = activeDownloads.first(where: { ($0.status == .downloading || $0.status == .converting) && $0.estimatedTimeRemaining != nil && ($0.estimatedTimeRemaining ?? 0) > 0 }),
               let time = activeItem.estimatedTimeRemaining, time > 0 {
                let totalRemainingBytes = activeDownloads.reduce(Int64(0)) { sum, download in
                    let remaining = max(Int64(0), download.totalBytes - download.bytesDownloaded)
                    return sum + remaining
                }
                let activeRemaining = max(Int64(0), activeItem.totalBytes - activeItem.bytesDownloaded)
                if activeRemaining > 0 && totalRemainingBytes > 0 {
                    let speed = Double(activeRemaining) / time
                    if speed > 1024 {
                        let totalSeconds = Double(totalRemainingBytes) / speed
                        let hours = Int(totalSeconds) / 3600
                        let minutes = (Int(totalSeconds) % 3600) / 60
                        let secs = Int(totalSeconds) % 60
                        if hours > 0 {
                            let hrUnit = hours == 1 ? "hr" : "hrs"
                            if minutes > 0 {
                                return "\(hours) \(hrUnit) \(minutes) min\(minutes == 1 ? "" : "s") left"
                            } else {
                                return "\(hours) \(hrUnit) left"
                            }
                        } else if minutes > 0 {
                            return "\(minutes) min\(minutes == 1 ? "" : "s") left"
                        } else {
                            return "\(max(secs, 1)) sec left"
                        }
                    }
                }
                return activeItem.formattedTimeRemaining
            }
            return nil
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

    // MARK: - Downloads Content

    private var downloadedMovies: [BaseItemDto] {
        downloadManager.downloadedMovies.map { movie in
            if let id = movie.id, let liveItem = libraryViewModel.movies.first(where: { $0.id == id }) {
                return liveItem
            }
            return movie
        }
    }

    private var downloadedShows: [BaseItemDto] {
        viewModel.downloadedShows(downloadManager: downloadManager)
    }

    private var downloadedEpisodes: [BaseItemDto] {
        viewModel.downloadedEpisodes(downloadManager: downloadManager).map { episode in
            if let id = episode.id,
               let liveItem = libraryViewModel.resumeShows.first(where: { $0.id == id }) ?? libraryViewModel.episodes.first(where: { $0.id == id }) {
                return liveItem
            }
            return episode
        }
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
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .scale(scale: 0.95)),
                                    removal: .opacity.combined(with: .scale(scale: 0.85))
                                ))
                        }
                        let standaloneItems = standaloneDownloads(from: items, groupedIDs: Set(groups.map(\.id)))
                        ForEach(standaloneItems) { downloadItem in
                            activeDownloadRow(downloadItem)
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .scale(scale: 0.95)),
                                    removal: .opacity.combined(with: .scale(scale: 0.85))
                                ))
                        }
                    } else {
                        ForEach(items) { downloadItem in
                            activeDownloadRow(downloadItem)
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .scale(scale: 0.95)),
                                    removal: .opacity.combined(with: .scale(scale: 0.85))
                                ))
                        }
                    }
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: items.map(\.id))
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - Download Action Icons & Styling

    private let cancelIcon = "square.fill"
    private let chevronIcon = "chevron.right"
    private let showPlaceholderIcon = "tv"
    private let moviePlaceholderIcon = "film"
    private let episodePlaceholderIcon = "tv"

    private let cancelIconColor = Color.mainOpp
    private let downloadActionIconFont = Font.system(size: 17, weight: .bold)
    private let downloadActionButtonSize: CGFloat = 26

    private struct DownloadActionButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.78 : 1.0)
                .opacity(configuration.isPressed ? 0.65 : 1.0)
                .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
        }
    }

    @ViewBuilder
    private func downloadActionButton(
        icon: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                action()
            }
        } label: {
            Image(systemName: icon)
                .font(downloadActionIconFont)
                .foregroundStyle(color)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: downloadActionButtonSize, height: downloadActionButtonSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(DownloadActionButtonStyle())
    }

    // MARK: - Download Thumbnail Helpers

    private func episodeThumbnailURL(for episode: BaseItemDto, client: JellyfinClient) -> URL? {
        guard let id = episode.id else { return nil }
        let hasThumb = episode.imageTags?.keys.contains("Thumb") == true
        let hasPrimary = episode.imageTags?.keys.contains("Primary") == true
        if hasThumb || hasPrimary {
            let imageType = hasThumb ? "Thumb" : "Primary"
            return client.url(with: Paths.getItemImage(
                itemID: id,
                imageType: imageType,
                parameters: .init(maxWidth: 400, quality: 80)
            ))
        }
        return libraryViewModel.seriesPosterURL(for: episode, client: client)
    }

    private func showPosterURL(for group: ShowDownloadGroup, client: JellyfinClient) -> URL? {
        if let show = libraryViewModel.tvShows.first(where: { $0.id == group.id }) {
            return libraryViewModel.posterURL(for: show, client: client)
        }
        if let first = group.representativeItem {
            return libraryViewModel.seriesPosterURL(for: first, client: client)
        }
        return client.url(with: Paths.getItemImage(
            itemID: group.id,
            imageType: "Primary",
            parameters: .init(maxWidth: 400, quality: 80)
        ))
    }

    private func mediaThumbnailURL(for item: BaseItemDto, client: JellyfinClient) -> URL? {
        if item.type == .episode {
            return episodeThumbnailURL(for: item, client: client)
        } else {
            return libraryViewModel.posterURL(for: item, client: client)
        }
    }

    @ViewBuilder
    private func downloadThumbnail(url: URL?, isEpisode: Bool, placeholderIcon: String) -> some View {
        let width: CGFloat = isEpisode ? 86 : 38
        let height: CGFloat = 54

        ZStack {
            Color.subTwo
            if let url {
                WebImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Image(systemName: placeholderIcon)
                        .font(.system(size: isEpisode ? 20 : 18))
                        .foregroundStyle(Color.accentColor.opacity(0.8))
                }
            } else {
                Image(systemName: placeholderIcon)
                    .font(.system(size: isEpisode ? 20 : 18))
                    .foregroundStyle(Color.accentColor.opacity(0.8))
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func showDownloadRow(_ group: ShowDownloadGroup) -> some View {
        HStack(spacing: 14) {
            Button {
                selectedShowDownloads = group
            } label: {
                HStack(spacing: 14) {
                    downloadThumbnail(
                        url: serverViewModel.client.flatMap { showPosterURL(for: group, client: $0) },
                        isEpisode: false,
                        placeholderIcon: showPlaceholderIcon
                    )

                    VStack(alignment: .leading, spacing: 6) {
                        Text(group.seriesName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.mainOpp)
                            .lineLimit(1)

                        ProgressView(value: group.overallProgress)
                            .tint(Color.accentColor)

                        HStack {
                            let subtitle: String = {
                                if group.isAllFailed {
                                    return "\(group.episodesLeft) \(group.episodesLeft == 1 ? "episode" : "episodes") left (Failed)"
                                } else if let timeRemaining = group.formattedTimeRemaining {
                                    return "\(group.episodesLeft) left • \(timeRemaining)"
                                } else {
                                    return "\(group.episodesLeft) \(group.episodesLeft == 1 ? "episode" : "episodes") left"
                                }
                            }()

                            let activeIcon: String? = {
                                if group.activeDownloads.contains(where: { $0.status == .converting }) {
                                    return "arrow.triangle.2.circlepath"
                                } else if group.activeDownloads.contains(where: { $0.status == .downloading }) {
                                    return "arrow.down"
                                }
                                return nil
                            }()

                            HStack(spacing: 4) {
                                if let icon = activeIcon {
                                    Image(systemName: icon)
                                        .font(.system(size: 11, weight: .medium))
                                }
                                Text(subtitle)
                            }
                            .font(.system(size: 12))
                            .foregroundStyle(Color.mainOpp.opacity(0.6))

                            Spacer()

                            Text("\(Int(group.overallProgress * 100))%")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color.mainOpp.opacity(0.8))
                        }
                    }
                }
            }
            .buttonStyle(.plain)

            HStack(spacing: 8) {
                downloadActionButton(icon: cancelIcon, color: cancelIconColor) {
                    groupToCancel = group
                }

                Button {
                    selectedShowDownloads = group
                } label: {
                    Image(systemName: chevronIcon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.mainOpp.opacity(0.5))
                        .frame(width: 20, height: downloadActionButtonSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(Color.sub, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func activeDownloadRow(_ downloadItem: DownloadItem) -> some View {
        let isEpisode = downloadItem.item.type == .episode
        let thumbURL = serverViewModel.client.flatMap { mediaThumbnailURL(for: downloadItem.item, client: $0) }

        return HStack(spacing: 14) {
            downloadThumbnail(
                url: thumbURL,
                isEpisode: isEpisode,
                placeholderIcon: isEpisode ? episodePlaceholderIcon : moviePlaceholderIcon
            )

            VStack(alignment: .leading, spacing: 6) {
                Text(downloadItem.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.mainOpp)
                    .lineLimit(1)

                if downloadItem.status == .failed {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.red)
                        Text(downloadItem.errorMessage ?? "Download or conversion failed")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.red)
                            .lineLimit(1)
                    }
                } else {
                    ProgressView(value: downloadItem.progress)
                        .tint(Color.accentColor)

                    HStack {
                        HStack(spacing: 4) {
                            if let icon = downloadItem.statusIcon {
                                Image(systemName: icon)
                                    .font(.system(size: 11, weight: .medium))
                            }
                            Text(downloadItem.statusText)
                        }
                        .font(.system(size: 12))
                        .foregroundStyle(Color.mainOpp.opacity(0.6))

                        Spacer()

                        if downloadItem.status != .queued {
                            Text(downloadItem.formattedPercentage)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color.mainOpp.opacity(0.8))
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                if downloadItem.status == .failed {
                    // Retry button
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            downloadManager.resumeDownload(id: downloadItem.id, client: serverViewModel.client)
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.mainOpp)
                            .frame(width: downloadActionButtonSize, height: downloadActionButtonSize)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(DownloadActionButtonStyle())

                    // Remove / Acknowledge button
                    Button {
                        itemToCancel = downloadItem
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                            Text("Remove")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(Color.red)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.red.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(DownloadActionButtonStyle())
                } else {
                    downloadActionButton(icon: cancelIcon, color: cancelIconColor) {
                        itemToCancel = downloadItem
                    }
                }
            }
        }
        .padding(14)
        .background(Color.sub, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var emptyDownloadsView: some View {
        EmptyStateView(
            icon: "square.and.arrow.down",
            title: "No Downloads",
            message: "You haven't downloaded any \(viewModel.filter.title.lowercased()) yet."
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
