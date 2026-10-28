//
//  DownloadsSheet.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 10/23/26.
//

import SwiftUI
import BaseColors
import JellyfinAPI
import SDWebImageSwiftUI

// MARK: - Downloads Sheet Configuration

enum DownloadsSheetMode: Equatable {
    case allActive
    case series(id: String, name: String)
}

struct DownloadsSheet: View {
    // MARK: - Customization Properties

    let initialMode: DownloadsSheetMode
    var customTitle: String?
    var allowsDrillDown: Bool
    var showsCompletedInSeries: Bool
    var showsTopBar: Bool?
    var customDetents: Set<PresentationDetent>?
    var onDismiss: (() -> Void)?

    // MARK: - Initializers

    /// Overview of all active downloads (replaces MinimalActiveDownloadsSheet).
    init(
        customTitle: String? = nil,
        allowsDrillDown: Bool = true,
        showsTopBar: Bool? = nil,
        customDetents: Set<PresentationDetent>? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        self.initialMode = .allActive
        self.customTitle = customTitle
        self.allowsDrillDown = allowsDrillDown
        self.showsCompletedInSeries = true
        self.showsTopBar = showsTopBar
        self.customDetents = customDetents
        self.onDismiss = onDismiss
    }

    /// Series-specific downloads sheet (replaces ShowDownloadsSheet).
    init(
        seriesID: String,
        seriesName: String,
        customTitle: String? = nil,
        showsCompletedInSeries: Bool = true,
        showsTopBar: Bool? = nil,
        customDetents: Set<PresentationDetent>? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        self.initialMode = .series(id: seriesID, name: seriesName)
        self.customTitle = customTitle
        self.allowsDrillDown = false
        self.showsCompletedInSeries = showsCompletedInSeries
        self.showsTopBar = showsTopBar
        self.customDetents = customDetents
        self.onDismiss = onDismiss
    }

    /// Mode-based initializer for flexible programmatic control.
    init(
        mode: DownloadsSheetMode,
        customTitle: String? = nil,
        allowsDrillDown: Bool = true,
        showsCompletedInSeries: Bool = true,
        showsTopBar: Bool? = nil,
        customDetents: Set<PresentationDetent>? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        self.initialMode = mode
        self.customTitle = customTitle
        self.allowsDrillDown = allowsDrillDown
        self.showsCompletedInSeries = showsCompletedInSeries
        self.showsTopBar = showsTopBar
        self.customDetents = customDetents
        self.onDismiss = onDismiss
    }

    // MARK: - Environment

    @Environment(DownloadManager.self) private var downloadManager
    @Environment(ServerViewModel.self) private var serverViewModel
    @Environment(LibraryViewModel.self) private var libraryViewModel
    @Environment(\.dismiss) private var dismiss

    // MARK: - State

    @State private var selectedGroup: ShowDownloadGroup?
    @State private var itemToCancel: DownloadItem?
    @State private var itemToDelete: DownloadItem?
    @State private var groupToCancel: ShowDownloadGroup?
    @State private var showCancelAllAlert = false
    @State private var isScrolledUnder = false
    @State private var topBarHeight: CGFloat = 0
    @State private var listHeight: CGFloat = 0

    // MARK: - Main Row Items (Overview Mode)

    private enum MainViewRowItem: Identifiable {
        case group(ShowDownloadGroup)
        case item(DownloadItem)

        var id: String {
            switch self {
            case .group(let group): return "group-\(group.id)"
            case .item(let item): return "item-\(item.id)"
            }
        }

        var startDate: Date {
            switch self {
            case .group(let group):
                let dates = (group.activeDownloads + group.completedDownloads).map(\.dateAdded)
                return dates.min() ?? .distantPast
            case .item(let item):
                return item.dateAdded
            }
        }
    }

    // MARK: - Mode & Navigation State

    private var activeSeriesID: String? {
        if let selectedGroup {
            return selectedGroup.id
        }
        if case .series(let id, _) = initialMode {
            return id
        }
        return nil
    }

    private var activeSeriesName: String? {
        if let selectedGroup {
            return selectedGroup.seriesName
        }
        if case .series(_, let name) = initialMode {
            return name
        }
        return nil
    }

    private var isDisplayingSeries: Bool {
        activeSeriesID != nil
    }

    private var canNavigateBack: Bool {
        selectedGroup != nil
    }

    // MARK: - Overview Computations

    private var activeDownloads: [DownloadItem] {
        downloadManager.activeDownloads
    }

    private var groups: [ShowDownloadGroup] {
        DownloadGrouping.groups(from: activeDownloads, completed: downloadManager.completedDownloads)
    }

    private var standaloneItems: [DownloadItem] {
        DownloadGrouping.standaloneDownloads(from: activeDownloads, groupedIDs: Set(groups.map(\.id)))
    }

    private var orderedMainViewItems: [MainViewRowItem] {
        let groupRows = groups.map { MainViewRowItem.group($0) }
        let standaloneRows = standaloneItems.map { MainViewRowItem.item($0) }
        return (groupRows + standaloneRows).sorted { $0.startDate < $1.startDate }
    }

    private var overviewProgress: Double {
        guard !activeDownloads.isEmpty else { return 0 }
        return activeDownloads.reduce(0.0) { $0 + $1.progress } / Double(activeDownloads.count)
    }

    private var overviewSubtitleText: String {
        let count = activeDownloads.count
        let allEpisodes = !activeDownloads.isEmpty && activeDownloads.allSatisfy { $0.item.type == .episode }
        let word = allEpisodes ? (count == 1 ? "episode" : "episodes") : (count == 1 ? "item" : "items")
        let percent = Int((overviewProgress * 100).rounded())
        return "\(count) \(word) left • \(percent)%"
    }

    // MARK: - Series Computations

    private var allSeriesDownloads: [DownloadItem] {
        guard let seriesID = activeSeriesID, let seriesName = activeSeriesName else { return [] }
        return Array(downloadManager.downloads.values).filter { download in
            download.group?.id == seriesID ||
            download.item.seriesID == seriesID ||
            download.item.parentBackdropItemID == seriesID ||
            download.item.seriesName == seriesName
        }
    }

    private var displayedSeriesDownloads: [DownloadItem] {
        let base = showsCompletedInSeries ? allSeriesDownloads : allSeriesDownloads.filter { $0.status != .completed }
        return base.sorted { a, b in
            let sA = a.item.parentIndexNumber ?? 1
            let sB = b.item.parentIndexNumber ?? 1
            if sA != sB { return sA < sB }
            let eA = a.item.indexNumber ?? 1
            let eB = b.item.indexNumber ?? 1
            if eA != eB { return eA < eB }
            return a.title.localizedStandardCompare(b.title) == .orderedAscending
        }
    }

    private var seriesActiveDownloads: [DownloadItem] {
        allSeriesDownloads.filter { $0.status != .completed }
    }

    private var seriesCompletedDownloads: [DownloadItem] {
        allSeriesDownloads.filter { $0.status == .completed }
    }

    private var isSeriesCollection: Bool {
        allSeriesDownloads.first?.group?.type == .collection || allSeriesDownloads.allSatisfy { $0.item.type != .episode }
    }

    private var seriesProgress: Double {
        guard !allSeriesDownloads.isEmpty else { return 0 }
        let completed = Double(seriesCompletedDownloads.count)
        let active = seriesActiveDownloads.reduce(0.0) { $0 + $1.progress }
        return (completed + active) / Double(allSeriesDownloads.count)
    }

    private var seriesSubtitleText: String {
        let count = seriesActiveDownloads.count
        let word = isSeriesCollection ? (count == 1 ? "item" : "items") : (count == 1 ? "episode" : "episodes")
        let percent = Int((seriesProgress * 100).rounded())
        return "\(count) \(word) left • \(percent)%"
    }

    // MARK: - Title & Top Bar Display

    private var resolvedTitle: String {
        if let customTitle {
            return customTitle
        }
        if isDisplayingSeries {
            return activeSeriesName ?? "Downloads"
        }
        return "Downloads"
    }

    private var resolvedSubtitleText: String {
        isDisplayingSeries ? seriesSubtitleText : overviewSubtitleText
    }

    private var resolvedProgress: Double {
        isDisplayingSeries ? seriesProgress : overviewProgress
    }

    private var hasActiveItems: Bool {
        isDisplayingSeries ? !seriesActiveDownloads.isEmpty : !activeDownloads.isEmpty
    }

    private var shouldShowTopBar: Bool {
        if let showsTopBar {
            return showsTopBar
        }
        if isDisplayingSeries {
            return !displayedSeriesDownloads.isEmpty
        }
        return orderedMainViewItems.count > 1
    }

    // MARK: - Presentation Detents

    @MainActor
    private var halfScreenHeight: CGFloat {
        #if canImport(UIKit)
        if let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first,
           let window = windowScene.windows.first(where: { $0.isKeyWindow }) ?? windowScene.windows.first {
            return window.bounds.height * 0.5
        }
        #endif
        return 420
    }

    private var presentationDetents: Set<PresentationDetent> {
        if let customDetents {
            return customDetents
        }
        let topH = shouldShowTopBar ? topBarHeight : 0
        let spacing: CGFloat = shouldShowTopBar ? 16 : 24
        let total = topH + listHeight + spacing
        let minHeight: CGFloat = isDisplayingSeries ? 160 : 90
        if listHeight > 0 && total < halfScreenHeight {
            return [.height(max(minHeight, total))]
        } else {
            return [.fraction(0.5)]
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                if isDisplayingSeries {
                    seriesContentView
                } else {
                    overviewContentView
                }
            }
            .animation(.spring(response: 0.38, dampingFraction: 0.78), value: isDisplayingSeries)
            .animation(.spring(response: 0.38, dampingFraction: 0.78), value: shouldShowTopBar)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                (geometry.contentOffset.y + geometry.contentInsets.top) > 2
            } action: { _, isScrolled in
                isScrolledUnder = isScrolled
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if shouldShowTopBar {
                    integratedTopBar
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .toolbarVisibility(.hidden, for: .navigationBar)
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
                "Delete Download?",
                isPresented: Binding(
                    get: { itemToDelete != nil },
                    set: { if !$0 { itemToDelete = nil } }
                ),
                presenting: itemToDelete
            ) { item in
                Button("Delete", role: .destructive) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        downloadManager.deleteDownload(id: item.id)
                    }
                    itemToDelete = nil
                }
                Button("Cancel", role: .cancel) {
                    itemToDelete = nil
                }
            } message: { item in
                Text("Are you sure you want to delete '\(item.title)' from your device?")
            }
            .alert(
                "Cancel All Downloads?",
                isPresented: Binding(
                    get: { groupToCancel != nil },
                    set: { if !$0 { groupToCancel = nil } }
                ),
                presenting: groupToCancel
            ) { group in
                Button("Cancel All", role: .destructive) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        downloadManager.cancelDownloads(ids: group.activeDownloads.map(\.id))
                    }
                    groupToCancel = nil
                }
                Button("Keep", role: .cancel) {
                    groupToCancel = nil
                }
            } message: { group in
                Text("Are you sure you want to cancel all in-progress downloads for '\(group.seriesName)'?")
            }
            .alert(
                "Cancel All Downloads?",
                isPresented: $showCancelAllAlert
            ) {
                Button("Cancel All", role: .destructive) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        if isDisplayingSeries {
                            downloadManager.cancelDownloads(ids: seriesActiveDownloads.map(\.id))
                        } else {
                            downloadManager.cancelDownloads(ids: activeDownloads.map(\.id))
                        }
                    }
                }
                Button("Keep", role: .cancel) {}
            } message: {
                if isDisplayingSeries, let name = activeSeriesName {
                    Text("Are you sure you want to cancel all in-progress downloads for '\(name)'?")
                } else {
                    Text("Are you sure you want to cancel all in-progress downloads?")
                }
            }
        }
        .presentationDetents(presentationDetents)
        .presentationDragIndicator(.visible)
        .animation(.spring(response: 0.38, dampingFraction: 0.78), value: presentationDetents)
    }

    // MARK: - Overview Content View

    @ViewBuilder
    private var overviewContentView: some View {
        if !orderedMainViewItems.isEmpty {
            VStack(spacing: 10) {
                ForEach(orderedMainViewItems) { row in
                    Group {
                        switch row {
                        case .group(let group):
                            showDownloadRow(group)
                        case .item(let downloadItem):
                            overviewDownloadRow(for: downloadItem)
                        }
                    }
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.95)),
                        removal: .opacity.combined(with: .scale(scale: 0.85))
                    ))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, shouldShowTopBar ? 12 : 24)
            .animation(.spring(response: 0.38, dampingFraction: 0.78), value: orderedMainViewItems.map(\.id))
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { h in
                listHeight = h
            }
        } else {
            EmptyStateView(
                icon: "arrow.down.circle",
                title: "No Active Downloads",
                message: "Media you download will appear here while downloading."
            )
            .padding(.top, shouldShowTopBar ? 40 : 28)
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { h in
                listHeight = h
            }
        }
    }

    // MARK: - Series Content View

    @ViewBuilder
    private var seriesContentView: some View {
        if !displayedSeriesDownloads.isEmpty {
            VStack(spacing: 10) {
                ForEach(displayedSeriesDownloads) { episode in
                    seriesEpisodeRow(episode, isCompleted: episode.status == .completed)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.95)),
                            removal: .opacity.combined(with: .scale(scale: 0.85))
                        ))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .animation(.spring(response: 0.38, dampingFraction: 0.78), value: displayedSeriesDownloads.map(\.id))
            .animation(.spring(response: 0.38, dampingFraction: 0.78), value: displayedSeriesDownloads.map(\.status))
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { h in
                listHeight = h
            }
        } else {
            EmptyStateView(
                icon: "tv",
                title: "No Downloads",
                message: "No downloaded episodes found for \(activeSeriesName ?? "series")."
            )
            .padding(.top, 40)
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { h in
                listHeight = h
            }
        }
    }

    // MARK: - Integrated Top Bar

    private var integratedTopBar: some View {
        VStack(spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                if canNavigateBack {
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                            selectedGroup = nil
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Color.mainOpp)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(DownloadsSquareActionButtonStyle())
                    .transition(.opacity.combined(with: .scale(scale: 0.85)))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(resolvedTitle)
                        .font(isDisplayingSeries ? .system(.title3, design: .rounded, weight: .bold) : .system(.title2, design: .rounded, weight: .bold))
                        .foregroundStyle(Color.mainOpp)
                        .lineLimit(1)

                    if (isDisplayingSeries ? !allSeriesDownloads.isEmpty : !activeDownloads.isEmpty) {
                        Text(resolvedSubtitleText)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.mainOpp.opacity(0.6))
                    }
                }

                Spacer()

                if hasActiveItems {
                    Button {
                        showCancelAllAlert = true
                    } label: {
                        Image(systemName: "square.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Color.mainOpp)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(DownloadsSquareActionButtonStyle())
                    .transition(.opacity.combined(with: .scale(scale: 0.85)))
                }
            }

            if hasActiveItems {
                ProgressView(value: resolvedProgress)
                    .tint(Color.accentColor)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 12)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { h in
            topBarHeight = h
        }
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(isScrolledUnder ? 1 : 0)
                .ignoresSafeArea(edges: .top)
        )
        .overlay(alignment: .bottom) {
            Divider()
                .opacity(isScrolledUnder ? 0.35 : 0)
        }
        .animation(.easeInOut(duration: 0.2), value: isScrolledUnder)
        .animation(.spring(response: 0.38, dampingFraction: 0.78), value: hasActiveItems)
    }

    // MARK: - Overview Group Row

    private func showDownloadRow(_ group: ShowDownloadGroup) -> some View {
        HStack(spacing: 12) {
            Button {
                if allowsDrillDown {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                        selectedGroup = group
                    }
                }
            } label: {
                HStack(spacing: 12) {
                    DownloadThumbnailView(
                        group: group,
                        client: serverViewModel.client,
                        libraryViewModel: libraryViewModel,
                        size: .regular
                    )

                    VStack(alignment: .leading, spacing: 6) {
                        Text(group.seriesName)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.mainOpp)
                            .lineLimit(1)

                        ProgressView(value: group.overallProgress)
                            .tint(Color.accentColor)

                        HStack {
                            let itemWord = group.groupInfo?.type == .collection ? (group.episodesLeft == 1 ? "item" : "items") : (group.episodesLeft == 1 ? "episode" : "episodes")
                            let subtitle: String = {
                                if group.isAllFailed {
                                    return "\(group.episodesLeft) \(itemWord) left (Failed)"
                                } else if let timeRemaining = group.formattedTimeRemaining {
                                    return "\(group.episodesLeft) left • \(timeRemaining)"
                                } else {
                                    return "\(group.episodesLeft) \(itemWord) left"
                                }
                            }()

                            let activeIcon: String? = group.activeStatusIcon

                            HStack(spacing: 4) {
                                if let icon = activeIcon {
                                    Image(systemName: icon)
                                        .font(.system(size: 11, weight: .medium))
                                }
                                Text(subtitle)
                            }
                            .font(.system(size: 12, design: .rounded))
                            .foregroundStyle(Color.mainOpp.opacity(0.6))

                            Spacer()

                            Text("\(Int(group.overallProgress * 100))%")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(Color.mainOpp.opacity(0.8))
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HStack(spacing: 6) {
                Button {
                    groupToCancel = group
                } label: {
                    Image(systemName: "square.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.mainOpp)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(DownloadsSquareActionButtonStyle())

                if allowsDrillDown {
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                            selectedGroup = group
                        }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.mainOpp.opacity(0.35))
                            .frame(width: 16, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    // MARK: - Overview Standalone Download Row

    private func overviewDownloadRow(for downloadItem: DownloadItem) -> some View {
        HStack(spacing: 12) {
            DownloadThumbnailView(
                item: downloadItem,
                client: serverViewModel.client,
                libraryViewModel: libraryViewModel,
                size: .regular
            )

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(downloadItem.title)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.mainOpp)
                        .lineLimit(1)

                    if downloadItem.status == .failed {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.white, Color.red)
                    }
                }

                if downloadItem.status == .failed {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.red)
                        Text(downloadItem.errorMessage ?? "Download or conversion failed")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.red)
                            .lineLimit(1)
                    }
                } else {
                    ProgressView(value: downloadItem.progress)
                        .tint(Color.accentColor)

                    HStack {
                        HStack(spacing: 4) {
                            Image(systemName: downloadItem.statusIcon)
                                .font(.system(size: 10, weight: .medium))
                            Text(downloadItem.statusText)
                        }
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(Color.mainOpp.opacity(0.6))

                        Spacer()

                        if downloadItem.status != .queued {
                            Text(downloadItem.formattedPercentage)
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(Color.mainOpp.opacity(0.8))
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 4) {
                if downloadItem.status == .failed {
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            downloadManager.resumeDownload(id: downloadItem.id, client: serverViewModel.client)
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.mainOpp)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(DownloadsSquareActionButtonStyle())
                }

                Button {
                    itemToCancel = downloadItem
                } label: {
                    Image(systemName: "square.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.mainOpp)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(DownloadsSquareActionButtonStyle())
            }
        }
        .padding(14)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    // MARK: - Series Episode Row

    private func seriesEpisodeRow(_ downloadItem: DownloadItem, isCompleted: Bool) -> some View {
        HStack(spacing: 12) {
            DownloadThumbnailView(
                item: downloadItem,
                client: serverViewModel.client,
                libraryViewModel: libraryViewModel,
                size: .regular
            )

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(downloadItem.title)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.mainOpp)
                        .lineLimit(1)

                    if downloadItem.status == .failed {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.white, Color.red)
                    }
                }

                if isCompleted {
                    Text(downloadItem.formattedFileSize)
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(Color.mainOpp.opacity(0.6))
                } else if downloadItem.status == .failed {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.red)
                        Text(downloadItem.errorMessage ?? "Download or conversion failed")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.red)
                            .lineLimit(1)
                    }
                } else {
                    ProgressView(value: downloadItem.progress)
                        .tint(Color.accentColor)

                    HStack {
                        HStack(spacing: 4) {
                            Image(systemName: downloadItem.statusIcon)
                                .font(.system(size: 11, weight: .medium))
                            Text(downloadItem.statusText)
                        }
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(Color.mainOpp.opacity(0.6))

                        Spacer()

                        if downloadItem.status != .queued {
                            Text(downloadItem.formattedPercentage)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(Color.mainOpp.opacity(0.8))
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 4) {
                if isCompleted {
                    Button {
                        itemToDelete = downloadItem
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.red)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(DownloadsSquareActionButtonStyle())
                } else if downloadItem.status == .failed {
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            downloadManager.resumeDownload(id: downloadItem.id, client: serverViewModel.client)
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.mainOpp)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(DownloadsSquareActionButtonStyle())

                    Button {
                        itemToCancel = downloadItem
                    } label: {
                        Image(systemName: "square.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Color.mainOpp)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(DownloadsSquareActionButtonStyle())
                } else {
                    Button {
                        itemToCancel = downloadItem
                    } label: {
                        Image(systemName: "square.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Color.mainOpp)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(DownloadsSquareActionButtonStyle())
                }
            }
        }
        .padding(14)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

// MARK: - Square Action Button Style

private struct DownloadsSquareActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.78 : 1.0)
            .opacity(configuration.isPressed ? 0.65 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Compatibility Typealiases

typealias MinimalActiveDownloadsSheet = DownloadsSheet
typealias ShowDownloadsSheet = DownloadsSheet
