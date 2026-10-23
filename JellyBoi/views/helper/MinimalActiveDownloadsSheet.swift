//
//  MinimalActiveDownloadsSheet.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 10/19/26.
//

import SwiftUI
import BaseColors
import JellyfinAPI
import SDWebImageSwiftUI

struct MinimalActiveDownloadsSheet: View {
    @Environment(DownloadManager.self) private var downloadManager
    @Environment(ServerViewModel.self) private var serverViewModel
    @Environment(LibraryViewModel.self) private var libraryViewModel

    @State private var itemToCancel: DownloadItem?
    @State private var groupToCancel: ShowDownloadGroup?
    @State private var selectedShowDownloads: ShowDownloadGroup?
    @State private var showCancelAllAlert = false
    @State private var isScrolledUnder = false
    @State private var topBarHeight: CGFloat = 0
    @State private var listHeight: CGFloat = 0

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

    private var showTitleArea: Bool {
        orderedMainViewItems.count > 1
    }

    private var overallProgress: Double {
        guard !activeDownloads.isEmpty else { return 0 }
        return activeDownloads.reduce(0.0) { $0 + $1.progress } / Double(activeDownloads.count)
    }

    private var subtitleText: String {
        let count = activeDownloads.count
        let allEpisodes = !activeDownloads.isEmpty && activeDownloads.allSatisfy { $0.item.type == .episode }
        let word = allEpisodes ? (count == 1 ? "episode" : "episodes") : (count == 1 ? "item" : "items")
        let percent = Int((overallProgress * 100).rounded())
        return "\(count) \(word) left • \(percent)%"
    }

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
        let topH = showTitleArea ? topBarHeight : 0
        let spacing: CGFloat = showTitleArea ? 16 : 24
        let total = topH + listHeight + spacing
        if listHeight > 0 && total < halfScreenHeight {
            return [.height(max(90, total))]
        } else {
            return [.fraction(0.5)]
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if !orderedMainViewItems.isEmpty {
                    VStack(spacing: 10) {
                        ForEach(orderedMainViewItems) { row in
                            Group {
                                switch row {
                                case .group(let group):
                                    showDownloadRow(group)
                                case .item(let downloadItem):
                                    downloadRow(for: downloadItem)
                                }
                            }
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.95)),
                                removal: .opacity.combined(with: .scale(scale: 0.85))
                            ))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, showTitleArea ? 12 : 24)
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
                    .padding(.top, showTitleArea ? 40 : 28)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { h in
                        listHeight = h
                    }
                }
            }
            .animation(.spring(response: 0.38, dampingFraction: 0.78), value: orderedMainViewItems.isEmpty)
            .animation(.spring(response: 0.38, dampingFraction: 0.78), value: showTitleArea)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                (geometry.contentOffset.y + geometry.contentInsets.top) > 2
            } action: { _, isScrolled in
                isScrolledUnder = isScrolled
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if showTitleArea {
                    integratedTopBar
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .toolbarVisibility(.hidden, for: .navigationBar)
            .sheet(item: $selectedShowDownloads) { group in
                ShowDownloadsSheet(seriesID: group.id, seriesName: group.seriesName)
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
                        downloadManager.cancelDownloads(ids: activeDownloads.map(\.id))
                    }
                }
                Button("Keep", role: .cancel) {}
            } message: {
                Text("Are you sure you want to cancel all in-progress downloads?")
            }
        }
        .presentationDetents(presentationDetents)
        .presentationDragIndicator(.visible)
        .animation(.spring(response: 0.38, dampingFraction: 0.78), value: presentationDetents)
    }

    // MARK: - Integrated Top Bar

    private var integratedTopBar: some View {
        VStack(spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Downloads")
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .foregroundStyle(Color.mainOpp)
                        .lineLimit(1)

                    if !activeDownloads.isEmpty {
                        Text(subtitleText)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.mainOpp.opacity(0.6))
                    }
                }

                Spacer()

                if !activeDownloads.isEmpty {
                    Button {
                        showCancelAllAlert = true
                    } label: {
                        Image(systemName: "square.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.white)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(SquareActionButtonStyle())
                    .transition(.opacity.combined(with: .scale(scale: 0.85)))
                }
            }

            if !activeDownloads.isEmpty {
                ProgressView(value: overallProgress)
                    .tint(Color.accentColor)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .padding(.horizontal, 16)
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
        .animation(.spring(response: 0.38, dampingFraction: 0.78), value: activeDownloads.isEmpty)
    }

    // MARK: - Group Row

    private func showDownloadRow(_ group: ShowDownloadGroup) -> some View {
        HStack(spacing: 12) {
            Button {
                selectedShowDownloads = group
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
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
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

                            let activeIcon: String? = {
                                if group.activeDownloads.contains(where: { $0.status == .converting || $0.status == .finalizing }) {
                                    return "arrow.triangle.2.circlepath"
                                } else if group.activeDownloads.contains(where: { $0.status == .downloading }) {
                                    return "arrow.down"
                                }
                                return nil
                            }()

                            HStack(spacing: 4) {
                                if let icon = activeIcon {
                                    Image(systemName: icon)
                                        .font(.system(size: 10, weight: .medium))
                                }
                                Text(subtitle)
                            }
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(Color.mainOpp.opacity(0.6))

                            Spacer()

                            Text("\(Int(group.overallProgress * 100))%")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
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
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.white)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(SquareActionButtonStyle())

                Button {
                    selectedShowDownloads = group
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.mainOpp.opacity(0.35))
                        .frame(width: 16, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Download Row

    private func downloadRow(for downloadItem: DownloadItem) -> some View {
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
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.mainOpp)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(SquareActionButtonStyle())
                }

                Button {
                    itemToCancel = downloadItem
                } label: {
                    Image(systemName: "square.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.white)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(SquareActionButtonStyle())
            }
        }
        .padding(14)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - Square Action Button Style

private struct SquareActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.78 : 1.0)
            .opacity(configuration.isPressed ? 0.65 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
