//
//  ShowDownloadsSheet.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 10/8/26.
//

import SwiftUI
import BaseColors
import JellyfinAPI

struct ShowDownloadsSheet: View {
    let seriesID: String
    let seriesName: String

    @Environment(DownloadManager.self) private var downloadManager
    @Environment(ServerViewModel.self) private var serverViewModel
    @Environment(\.dismiss) private var dismiss

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
                                Button("Cancel All", role: .destructive) {
                                    for item in activeEpisodes {
                                        downloadManager.cancelDownload(id: item.id)
                                    }
                                }
                                .font(.subheadline)
                            }
                        }

                        ProgressView(value: overallProgress)
                            .tint(Color.accentColor)
                    }
                    .padding(16)
                    .background(Color.mainOpp.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(.horizontal, 16)

                    // Active downloads
                    if !activeEpisodes.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Downloading (\(activeEpisodes.count))")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(Color.mainOpp)
                                .padding(.horizontal, 16)

                            VStack(spacing: 10) {
                                ForEach(activeEpisodes) { downloadItem in
                                    episodeDownloadRow(downloadItem, isCompleted: false)
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }

                    // Completed downloads
                    if !completedEpisodes.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Downloaded (\(completedEpisodes.count))")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(Color.mainOpp)
                                .padding(.horizontal, 16)

                            VStack(spacing: 10) {
                                ForEach(completedEpisodes) { downloadItem in
                                    episodeDownloadRow(downloadItem, isCompleted: true)
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                }
                .padding(.vertical, 16)
            }
            .navigationTitle("Downloads")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func episodeDownloadRow(_ downloadItem: DownloadItem, isCompleted: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: isCompleted ? "checkmark.circle.fill" : "tv")
                .font(.system(size: 20))
                .foregroundStyle(isCompleted ? Color.green : Color.accentColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 5) {
                Text(episodeTitle(for: downloadItem.item))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.mainOpp)
                    .lineLimit(1)

                if !isCompleted {
                    ProgressView(value: downloadItem.progress)
                        .tint(Color.accentColor)

                    HStack {
                        Text(downloadItem.status == .paused ? "Paused" : downloadItem.formattedProgress)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.mainOpp.opacity(0.6))

                        Spacer()

                        Text(downloadItem.formattedPercentage)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.mainOpp.opacity(0.8))
                    }
                } else {
                    Text(downloadItem.formattedProgress)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.mainOpp.opacity(0.6))
                }
            }

            HStack(spacing: 6) {
                if !isCompleted {
                    if downloadItem.status == .downloading {
                        Button {
                            downloadManager.pauseDownload(id: downloadItem.id)
                        } label: {
                            Image(systemName: "pause.circle.fill")
                                .font(.system(size: 22))
                                .foregroundStyle(Color.mainOpp.opacity(0.8))
                        }
                        .buttonStyle(.plain)
                    } else if downloadItem.status == .paused {
                        Button {
                            downloadManager.resumeDownload(id: downloadItem.id, client: serverViewModel.client)
                        } label: {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 22))
                                .foregroundStyle(Color.accentColor)
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        downloadManager.cancelDownload(id: downloadItem.id)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(Color.mainOpp.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        downloadManager.deleteDownload(id: downloadItem.id)
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.red.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .background(Color.mainOpp.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func episodeTitle(for item: BaseItemDto) -> String {
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
