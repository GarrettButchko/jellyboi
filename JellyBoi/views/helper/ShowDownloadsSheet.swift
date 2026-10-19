//
//  ShowDownloadsSheet.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 10/8/26.
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
    @Environment(\.dismiss) private var dismiss
    @State private var itemToCancel: DownloadItem?
    @State private var itemToDelete: DownloadItem?
    @State private var showCancelAllAlert = false

    private var activeEpisodes: [DownloadItem] {
        downloadManager.activeDownloads.filter {
            $0.item.seriesID == seriesID ||
            $0.item.parentBackdropItemID == seriesID ||
            ($0.item.type == .episode && $0.item.seriesName == seriesName)
        }
    }

    private var completedEpisodes: [DownloadItem] {
        downloadManager.completedDownloads.filter {
            $0.item.seriesID == seriesID ||
            $0.item.parentBackdropItemID == seriesID ||
            ($0.item.type == .episode && $0.item.seriesName == seriesName)
        }
    }

    private var episodesLeft: Int {
        activeEpisodes.count
    }

    private var totalEpisodes: Int {
        activeEpisodes.count + completedEpisodes.count
    }

    private var overallProgress: Double {
        guard totalEpisodes > 0 else { return 0 }
        let completed = Double(completedEpisodes.count)
        let active = activeEpisodes.reduce(0.0) { $0 + $1.progress }
        return (completed + active) / Double(totalEpisodes)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Summary header card
                    ShowDownloadsSummaryHeader(
                        seriesName: seriesName,
                        episodesLeft: episodesLeft,
                        totalEpisodes: totalEpisodes,
                        overallProgress: overallProgress,
                        onCancelAll: {
                            showCancelAllAlert = true
                        }
                    )

                    // Active downloads
                    if !activeEpisodes.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Preparing (\(activeEpisodes.count))")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(Color.mainOpp)
                                .padding(.horizontal, 16)

                            VStack(spacing: 10) {
                                ForEach(activeEpisodes) { downloadItem in
                                    EpisodeDownloadRow(
                                        downloadItem: downloadItem,
                                        isCompleted: false,
                                        client: serverViewModel.client,
                                        libraryViewModel: libraryViewModel,
                                        onCancel: {
                                            itemToCancel = downloadItem
                                        },
                                        onRetry: {
                                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                                downloadManager.resumeDownload(id: downloadItem.id, client: serverViewModel.client)
                                            }
                                        },
                                        onDelete: {
                                            itemToDelete = downloadItem
                                        }
                                    )
                                    .equatable()
                                    .transition(.asymmetric(
                                        insertion: .opacity.combined(with: .scale(scale: 0.95)),
                                        removal: .opacity.combined(with: .scale(scale: 0.85))
                                    ))
                                }
                            }
                            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: activeEpisodes.map(\.id))
                            .padding(.horizontal, 16)
                        }
                    }

                    // Completed downloads
                    if !completedEpisodes.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Finished (\(completedEpisodes.count))")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(Color.mainOpp)
                                .padding(.horizontal, 16)

                            VStack(spacing: 10) {
                                ForEach(completedEpisodes) { downloadItem in
                                    EpisodeDownloadRow(
                                        downloadItem: downloadItem,
                                        isCompleted: true,
                                        client: serverViewModel.client,
                                        libraryViewModel: libraryViewModel,
                                        onCancel: {
                                            itemToCancel = downloadItem
                                        },
                                        onRetry: {
                                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                                downloadManager.resumeDownload(id: downloadItem.id, client: serverViewModel.client)
                                            }
                                        },
                                        onDelete: {
                                            itemToDelete = downloadItem
                                        }
                                    )
                                    .equatable()
                                    .transition(.asymmetric(
                                        insertion: .opacity.combined(with: .scale(scale: 0.95)),
                                        removal: .opacity.combined(with: .scale(scale: 0.85))
                                    ))
                                }
                            }
                            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: completedEpisodes.map(\.id))
                            .padding(.horizontal, 16)
                        }
                    }
                }
                .padding(.vertical, 16)
            }
            .background(Color.bg.ignoresSafeArea())
            .navigationTitle("Downloads")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
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
                    Text("Are you sure you want to cancel the download for '\(Self.episodeTitle(for: item.item))'?")
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
                Text("Are you sure you want to delete '\(Self.episodeTitle(for: item.item))' from your downloads?")
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
        .presentationBackground(Color.bg)
    }

    static func episodeTitle(for item: BaseItemDto) -> String {
        var label = ""
        if let season = item.parentIndexNumber, let episode = item.indexNumber {
            label = "S\(season):E\(episode)"
        }
        if let name = item.name, !name.isEmpty {
            label = label.isEmpty ? name : "\(label) • \(name)"
        }
        return label.isEmpty ? (item.name ?? "Episode") : label
    }
}

// MARK: - Summary Header

private struct ShowDownloadsSummaryHeader: View {
    let seriesName: String
    let episodesLeft: Int
    let totalEpisodes: Int
    let overallProgress: Double
    let onCancelAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(seriesName)
                        .font(.headline)
                        .foregroundStyle(Color.mainOpp)
                        .lineLimit(1)

                    Text(episodesLeft > 0 ? "\(episodesLeft) of \(totalEpisodes) episodes left" : "All episodes downloaded")
                        .font(.subheadline)
                        .foregroundStyle(Color.mainOpp.opacity(0.7))
                }

                Spacer()

                if episodesLeft > 0 {
                    Button("Cancel", role: .destructive) {
                        onCancelAll()
                    }
                    .font(.subheadline)
                }
            }

            ProgressView(value: overallProgress)
                .tint(Color.accentColor)
        }
        .padding(16)
        .background(Color.sub, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 16)
    }
}

// MARK: - Episode Download Row

private struct EpisodeDownloadRow: View, Equatable {
    let downloadItem: DownloadItem
    let isCompleted: Bool
    let client: JellyfinClient?
    let libraryViewModel: LibraryViewModel
    let onCancel: () -> Void
    let onRetry: () -> Void
    let onDelete: () -> Void

    private let cancelIcon = "square.fill"
    private let deleteIcon = "trash"
    private let cancelIconColor = Color.mainOpp
    private let deleteIconColor = Color.red.opacity(0.8)
    private let actionButtonSize: CGFloat = 26
    private let actionButtonFont = Font.system(size: 17, weight: .bold)

    static func == (lhs: EpisodeDownloadRow, rhs: EpisodeDownloadRow) -> Bool {
        lhs.downloadItem == rhs.downloadItem &&
        lhs.isCompleted == rhs.isCompleted
    }

    var body: some View {
        HStack(spacing: 12) {
            EpisodeThumbnailView(
                downloadItem: downloadItem,
                client: client,
                libraryViewModel: libraryViewModel
            )

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(ShowDownloadsSheet.episodeTitle(for: downloadItem.item))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.mainOpp)
                        .lineLimit(1)

                    if isCompleted {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.white, Color.green)
                    } else if downloadItem.status == .failed {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.white, Color.red)
                    }
                }

                if isCompleted {
                    HStack(spacing: 6) {
                        Text(downloadItem.formatBadge)
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 4, style: .continuous))

                        Text(downloadItem.formattedFileSize)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.mainOpp.opacity(0.6))
                    }
                } else if downloadItem.status == .failed {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.red)
                        Text(downloadItem.errorMessage ?? "Download or conversion failed")
                            .font(.system(size: 11, weight: .medium))
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
                                    .font(.system(size: 10, weight: .medium))
                            }
                            Text(downloadItem.statusText)
                        }
                        .font(.system(size: 11))
                        .foregroundStyle(Color.mainOpp.opacity(0.6))

                        Spacer()

                        if downloadItem.status != .queued {
                            Text(downloadItem.formattedPercentage)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color.mainOpp.opacity(0.8))
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                if isCompleted {
                    actionButton(icon: deleteIcon, color: deleteIconColor) {
                        onDelete()
                    }
                } else if downloadItem.status == .failed {
                    // Retry button
                    Button {
                        onRetry()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.mainOpp)
                            .frame(width: actionButtonSize, height: actionButtonSize)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(ActionButtonStyle())

                    // Remove / Acknowledge button
                    Button {
                        onCancel()
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
                    .buttonStyle(ActionButtonStyle())
                } else {
                    actionButton(icon: cancelIcon, color: cancelIconColor) {
                        onCancel()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(Color.sub, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private func actionButton(
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
                .font(actionButtonFont)
                .foregroundStyle(color)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: actionButtonSize, height: actionButtonSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(ActionButtonStyle())
    }

    private struct ActionButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.78 : 1.0)
                .opacity(configuration.isPressed ? 0.65 : 1.0)
                .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
        }
    }
}

// MARK: - Episode Thumbnail

private struct EpisodeThumbnailView: View {
    let downloadItem: DownloadItem
    let client: JellyfinClient?
    let libraryViewModel: LibraryViewModel

    private var thumbnailURL: URL? {
        guard let client else { return nil }
        let episode = downloadItem.item
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

    var body: some View {
        ZStack {
            Color.subTwo
            if let thumbnailURL {
                WebImage(url: thumbnailURL) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Image(systemName: "tv")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.accentColor.opacity(0.8))
                }
            } else {
                Image(systemName: "tv")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.accentColor.opacity(0.8))
            }
        }
        .frame(width: 80, height: 46)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
