//
//  StorageSettingsView.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 11/04/26.
//

import SwiftUI
import BaseColors
import SDWebImage
import StatusOverlayKit

struct StorageSettingsView: View {
    @Environment(DownloadManager.self) private var downloadManager
    @Environment(\.dismiss) private var dismiss

    @State private var imageCacheBytes: UInt = 0
    @State private var downloadsBytes: Int64 = 0
    @State private var isClearingImageCache = false
    @State private var showDeleteAllDownloadsAlert = false

    var body: some View {
        List {
            // MARK: - Device Storage Overview
            Section {
                deviceStorageView
            } header: {
                Text("Device Storage")
            }

            // MARK: - Image Cache
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Image Cache")
                        Text("Thumbnails, posters, and backdrops cached for fast browsing.")
                            .font(.subheadline)
                            .foregroundStyle(Color.mainOpp.opacity(0.6))
                    }
                    Spacer()
                    Text(formattedBytes(Int64(imageCacheBytes)))
                        .foregroundStyle(Color.mainOpp.opacity(0.75))
                }
                .padding(.vertical, 4)

                Button(role: .destructive) {
                    clearImageCache()
                } label: {
                    HStack {
                        Text("Clear Image Cache")
                        Spacer()
                        if isClearingImageCache {
                            ProgressView()
                                .tint(.red)
                        }
                    }
                }
                .disabled(isClearingImageCache || imageCacheBytes == 0)
            } header: {
                Text("Artwork & Caches")
            } footer: {
                Text("Clearing image cache does not affect downloaded media files. Images will re-download when browsing.")
            }

            // MARK: - Downloads Storage
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Offline Media")
                        Text("\(downloadManager.downloads.count) item(s) saved for offline playback.")
                            .font(.subheadline)
                            .foregroundStyle(Color.mainOpp.opacity(0.6))
                    }
                    Spacer()
                    Text(formattedBytes(downloadsBytes))
                        .foregroundStyle(Color.mainOpp.opacity(0.75))
                }
                .padding(.vertical, 4)

                Button(role: .destructive) {
                    showDeleteAllDownloadsAlert = true
                } label: {
                    HStack {
                        Image(systemName: "trash")
                        Text("Delete All Downloads")
                    }
                }
                .disabled(downloadManager.downloads.isEmpty && downloadsBytes == 0)
            } header: {
                Text("Offline Downloads")
            } footer: {
                Text("Deleting all downloads will remove all stored media files and cannot be undone.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.bg.ignoresSafeArea())
        .navigationTitle("Storage & Cache")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            refreshSizes()
        }
        .confirmationDialog(
            "Delete All Downloads?",
            isPresented: $showDeleteAllDownloadsAlert,
            titleVisibility: .visible
        ) {
            Button("Delete All Downloads", role: .destructive) {
                downloadManager.deleteAllDownloads()
                refreshSizes()
                TransientStatusSignal.shared.pending = StatusMessage(
                    title: "Downloads Cleared",
                    subtitle: "All offline media files deleted",
                    icon: "trash",
                    tint: .red
                )
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete all downloaded movies, episodes, and remuxed video files from your device.")
        }
    }

    // MARK: - Device Storage View

    @ViewBuilder
    private var deviceStorageView: some View {
        let (available, total) = calculateDeviceCapacity()
        let used = max(0, total - available)
        let usedFraction = total > 0 ? Double(used) / Double(total) : 0.0

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Available Capacity")
                Spacer()
                Text("\(formattedBytes(available)) free of \(formattedBytes(total))")
                    .font(.subheadline)
                    .foregroundStyle(Color.mainOpp.opacity(0.6))
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.subTwo)
                        .frame(height: 8)

                    Capsule()
                        .fill(Color.blue)
                        .frame(width: max(8, proxy.size.width * usedFraction), height: 8)
                }
            }
            .frame(height: 8)

            HStack(spacing: 16) {
                HStack(spacing: 6) {
                    Circle().fill(Color.blue).frame(width: 8, height: 8)
                    Text("Used: \(formattedBytes(used))")
                        .font(.caption)
                        .foregroundStyle(Color.mainOpp.opacity(0.6))
                }
                HStack(spacing: 6) {
                    Circle().fill(Color.purple).frame(width: 8, height: 8)
                    Text("JellyBoi: \(formattedBytes(Int64(imageCacheBytes) + downloadsBytes))")
                        .font(.caption)
                        .foregroundStyle(Color.mainOpp.opacity(0.6))
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Helpers

    private func refreshSizes() {
        imageCacheBytes = SDImageCache.shared.totalDiskSize()
        downloadsBytes = calculateDownloadsDirectorySize()
    }

    private func clearImageCache() {
        isClearingImageCache = true
        SDImageCache.shared.clearMemory()
        SDImageCache.shared.clearDisk {
            DispatchQueue.main.async {
                self.isClearingImageCache = false
                self.refreshSizes()
                TransientStatusSignal.shared.pending = StatusMessage(
                    title: "Image Cache Cleared",
                    subtitle: "Freed artwork disk storage",
                    icon: "checkmark.circle.fill",
                    tint: .green
                )
            }
        }
    }

    private func calculateDownloadsDirectorySize() -> Int64 {
        let fileManager = FileManager.default
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let downloadsFolder = docs.appendingPathComponent("Downloads", isDirectory: true)

        guard let enumerator = fileManager.enumerator(
            at: downloadsFolder,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
               let size = resourceValues.fileSize {
                total += Int64(size)
            }
        }
        return total
    }

    private func calculateDeviceCapacity() -> (available: Int64, total: Int64) {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        guard let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]) else {
            return (0, 0)
        }
        let available = values.volumeAvailableCapacityForImportantUsage ?? 0
        let total = Int64(values.volumeTotalCapacity ?? 0)
        return (available, total)
    }

    private func formattedBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: max(0, bytes), countStyle: .file)
    }
}
