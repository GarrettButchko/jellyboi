//
//  ShowDownloadsSheet.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 10/21/26.
//

import SwiftUI
import BaseColors
import JellyfinAPI
import SDWebImageSwiftUI

struct ShowDownloadsSheet: View {
    let seriesID: String
    let seriesName: String

    @Environment(DownloadManager.self) private var downloadManager
    @Environment(ServerViewModel.self) private var serverViewModel
    @Environment(LibraryViewModel.self) private var libraryViewModel

    @State private var itemToCancel: DownloadItem?
    @State private var itemToDelete: DownloadItem?
    @State private var showCancelAllAlert = false
    @State private var isScrolledUnder = false
    @State private var topBarHeight: CGFloat = 0
    @State private var listHeight: CGFloat = 0

    private var allGroupDownloads: [DownloadItem] {
        Array(downloadManager.downloads.values).filter { download in
            download.group?.id == seriesID ||
            download.item.seriesID == seriesID ||
            download.item.parentBackdropItemID == seriesID ||
            download.item.seriesName == seriesName
        }
    }

    private var sortedEpisodes: [DownloadItem] {
        allGroupDownloads.sorted { a, b in
            let sA = a.item.parentIndexNumber ?? 1
            let sB = b.item.parentIndexNumber ?? 1
            if sA != sB { return sA < sB }
            let eA = a.item.indexNumber ?? 1
            let eB = b.item.indexNumber ?? 1
            if eA != eB { return eA < eB }
            return a.title.localizedStandardCompare(b.title) == .orderedAscending
        }
    }

    private var activeEpisodes: [DownloadItem] {
        allGroupDownloads.filter { $0.status != .completed }
    }

    private var completedEpisodes: [DownloadItem] {
        allGroupDownloads.filter { $0.status == .completed }
    }

    private var isCollection: Bool {
        allGroupDownloads.first?.group?.type == .collection || allGroupDownloads.allSatisfy { $0.item.type != .episode }
    }

    private var overallProgress: Double {
        guard !allGroupDownloads.isEmpty else { return 0 }
        let completed = Double(completedEpisodes.count)
        let active = activeEpisodes.reduce(0.0) { $0 + $1.progress }
        return (completed + active) / Double(allGroupDownloads.count)
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
        let total = topBarHeight + listHeight + 16
        if topBarHeight > 0 && listHeight > 0 && total < halfScreenHeight {
            return [.height(max(160, total))]
        } else {
            return [.fraction(0.5)]
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if !allGroupDownloads.isEmpty {
                    VStack(spacing: 10) {
                        ForEach(sortedEpisodes) { episode in
                            episodeRow(episode, isCompleted: episode.status == .completed)
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .scale(scale: 0.95)),
                                    removal: .opacity.combined(with: .scale(scale: 0.85))
                                ))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .animation(.spring(response: 0.38, dampingFraction: 0.78), value: sortedEpisodes.map(\.id))
                    .animation(.spring(response: 0.38, dampingFraction: 0.78), value: sortedEpisodes.map(\.status))
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { h in
                        listHeight = h
                    }
                } else {
                    EmptyStateView(
                        icon: "tv",
                        title: "No Downloads",
                        message: "No downloaded episodes found for \(seriesName)."
                    )
                    .padding(.top, 40)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { h in
                        listHeight = h
                    }
                }
            }
            .animation(.spring(response: 0.38, dampingFraction: 0.78), value: allGroupDownloads.isEmpty)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                (geometry.contentOffset.y + geometry.contentInsets.top) > 2
            } action: { _, isScrolled in
                isScrolledUnder = isScrolled
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                integratedTopBar
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
                isPresented: $showCancelAllAlert
            ) {
                Button("Cancel All", role: .destructive) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        downloadManager.cancelDownloads(ids: activeEpisodes.map(\.id))
                    }
                }
                Button("Keep", role: .cancel) {}
            } message: {
                Text("Are you sure you want to cancel all in-progress downloads for '\(seriesName)'?")
            }
        }
        .presentationDetents(presentationDetents)
        .presentationDragIndicator(.visible)
        .animation(.spring(response: 0.38, dampingFraction: 0.78), value: presentationDetents)
    }

    // MARK: - Integrated Top Bar

    private var subtitleText: String {
        let count = activeEpisodes.count
        let word = isCollection ? (count == 1 ? "item" : "items") : (count == 1 ? "episode" : "episodes")
        let percent = Int((overallProgress * 100).rounded())
        return "\(count) \(word) left • \(percent)%"
    }

    private var integratedTopBar: some View {
        VStack(spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(seriesName)
                        .font(.system(.headline, design: .rounded, weight: .bold))
                        .foregroundStyle(Color.mainOpp)
                        .lineLimit(1)

                    if !allGroupDownloads.isEmpty {
                        Text(subtitleText)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.mainOpp.opacity(0.6))
                    }
                }

                Spacer()

                if !activeEpisodes.isEmpty {
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

            if !activeEpisodes.isEmpty {
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
        .animation(.spring(response: 0.38, dampingFraction: 0.78), value: activeEpisodes.isEmpty)
    }

    // MARK: - Episode Row

    private func episodeRow(_ downloadItem: DownloadItem, isCompleted: Bool) -> some View {
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

                if isCompleted {
                    Text(downloadItem.formattedFileSize)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(Color.mainOpp.opacity(0.6))
                } else if downloadItem.status == .failed {
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
                if isCompleted {
                    Button {
                        itemToDelete = downloadItem
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.red)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(SquareActionButtonStyle())
                } else if downloadItem.status == .failed {
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
                } else {
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
