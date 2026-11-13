//
//  Manager+Queries.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 10/8/26.
//

import Foundation
import JellyfinAPI

// MARK: - Query State

extension DownloadManager {
    public var downloadList: [DownloadItem] {
        Array(downloads.values).sorted { $0.dateAdded > $1.dateAdded }
    }

    public var activeDownloads: [DownloadItem] {
        Array(downloads.values)
            .filter { $0.status == .downloading || $0.status == .converting || $0.status == .finalizing || $0.status == .queued || $0.status == .failed }
            .sorted { a, b in
                let aActive = a.status == .downloading || a.status == .converting || a.status == .finalizing
                let bActive = b.status == .downloading || b.status == .converting || b.status == .finalizing
                if aActive && !bActive { return true }
                if bActive && !aActive { return false }
                // Preserve episode order for the same series
                if let sA = a.item.parentIndexNumber, let sB = b.item.parentIndexNumber,
                   let eA = a.item.indexNumber, let eB = b.item.indexNumber,
                   (a.item.seriesID == b.item.seriesID || a.item.seriesName == b.item.seriesName) {
                    if sA != sB { return sA < sB }
                    return eA < eB
                }
                return a.dateAdded < b.dateAdded
            }
    }

    public var completedDownloads: [DownloadItem] {
        Array(downloads.values)
            .filter { item in
                guard item.status == .completed else { return false }
                return storage.fileExists(for: item.fileName)
            }
            .sorted { ($0.dateCompleted ?? $0.dateAdded) > ($1.dateCompleted ?? $1.dateAdded) }
    }

    public var hasActiveDownloads: Bool {
        !activeDownloads.isEmpty
    }

    public var hasCompletedDownloads: Bool {
        !completedDownloads.isEmpty
    }

    public var currentPresentation: DownloadSummaryPresentation {
        DownloadGrouping.currentPresentation(active: activeDownloads, completed: completedDownloads, client: client)
    }
}

// MARK: - Categorized Completed Media

extension DownloadManager {
    public var downloadedMovies: [BaseItemDto] {
        completedDownloads
            .map(\.item)
            .filter { $0.type == .movie || ($0.type != .series && $0.type != .episode && $0.type != .boxSet && $0.seriesName == nil) }
    }

    public var downloadedShows: [BaseItemDto] {
        var shows: [BaseItemDto] = []
        var seenIDs = Set<String>()

        for download in completedDownloads where download.item.type == .series {
            if let id = download.item.id, seenIDs.insert(id).inserted {
                shows.append(download.item)
            }
        }

        for download in completedDownloads where download.item.type == .episode || download.item.seriesName != nil {
            let episode = download.item
            let seriesID = episode.seriesID ?? episode.parentBackdropItemID
            let seriesName = episode.seriesName
            if let seriesID, seenIDs.insert(seriesID).inserted {
                shows.append(BaseItemDto(
                    id: seriesID,
                    name: seriesName,
                    type: .series
                ))
            }
        }

        return shows
    }

    public var downloadedEpisodes: [BaseItemDto] {
        completedDownloads
            .map(\.item)
            .filter { $0.type == .episode || $0.seriesName != nil }
    }

    public var downloadedCollections: [BaseItemDto] {
        completedDownloads
            .map(\.item)
            .filter { $0.type == .boxSet }
    }
}

// MARK: - Lookups

extension DownloadManager {
    public func isDownloaded(id: String) -> Bool {
        guard let item = downloads[id], item.status == .completed else { return false }
        return storage.fileExists(for: item.fileName)
    }

    public func isDownloading(id: String) -> Bool {
        guard let item = downloads[id] else { return false }
        return item.status == .downloading || item.status == .converting || item.status == .finalizing || item.status == .queued
    }

    public func downloadItem(for id: String) -> DownloadItem? {
        downloads[id]
    }

    public func progress(for id: String) -> Double? {
        guard let item = downloads[id] else { return nil }
        return item.progress
    }

    public func localFileURL(for id: String) -> URL? {
        guard let record = downloads[id] else { return nil }
        return storage.localFileURL(for: record.fileName)
    }

    public func playableLocalFileURL(for id: String) -> URL? {
        #if DEBUG
        if DebugSettings.shared.forceStreamFallback { return nil }
        #endif
        // Only a finished download in a container AVPlayer opens natively is worth attempting
        // offline; anything else would just fail and fall back to streaming.
        guard let record = downloads[id],
              record.status == .completed,
              let url = localFileURL(for: id),
              ApplePlayableContainer.canPlay(url: url) else { return nil }
        return url
    }
}

// MARK: - Playback Progress & Metadata Sync

extension DownloadManager {
    public func updateProgress(for itemID: String, positionTicks: Int, totalTicks: Int?) {
        guard var downloadItem = downloads[itemID] else { return }
        downloadItem.item.updateProgress(positionTicks: positionTicks, totalTicks: totalTicks)
        downloads[itemID] = downloadItem
        saveIndex()
    }

    /// Applies server-reported user data to downloaded items so their progress and favorite state
    /// always match the server.
    public func applyUserData(_ dtos: [UserItemDataDto]) {
        var changed = false

        for dto in dtos {
            let itemID = dto.itemID ?? dto.key
            guard var downloadItem = downloads[itemID] else { continue }
            downloadItem.item.userData = dto
            downloads[itemID] = downloadItem
            changed = true
        }

        if changed {
            saveIndex()
        }
    }
}
