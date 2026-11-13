//
//  Manager+Downloads.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 10/8/26.
//

import Foundation
import JellyfinAPI
import LoggingKit
import SDWebImage

// MARK: - Starting Downloads

extension DownloadManager {
    public func startDownload(item: BaseItemDto, client: JellyfinClient, group: DownloadGroupInfo? = nil) {
        DownloadNotificationManager.shared.requestAuthorizationIfNeeded()
        self.client = client
        enqueue(item: item, client: client, group: group)
        saveIndex()
        processQueue()
        updateLiveActivity(force: true)
    }

    public func startDownloads(items: [BaseItemDto], client: JellyfinClient, group: DownloadGroupInfo? = nil) {
        DownloadNotificationManager.shared.requestAuthorizationIfNeeded()
        self.client = client
        for item in items {
            enqueue(item: item, client: client, group: group)
        }
        saveIndex()
        processQueue()
        updateLiveActivity(force: true)
    }

    private func enqueue(item: BaseItemDto, client: JellyfinClient, group: DownloadGroupInfo? = nil) {
        guard let itemID = item.id else {
            AppLogger.warning("Cannot download item without ID")
            return
        }

        if let existing = downloads[itemID], existing.status == .completed, localFileURL(for: itemID) != nil {
            AppLogger.info("Item '\(item.name ?? itemID)' is already downloaded")
            return
        }

        if let existing = downloads[itemID], existing.status == .downloading || existing.status == .converting || existing.status == .finalizing || existing.status == .queued {
            AppLogger.info("Item '\(item.name ?? itemID)' is already downloading or queued")
            return
        }

        let container = item.container?.lowercased() ?? "mp4"
        let safeContainer = container.isEmpty ? "mp4" : container
        let isNativePlayable = ApplePlayableContainer.supports(safeContainer)
        let finalContainer = isNativePlayable ? safeContainer : "mp4"
        let fileName = "\(itemID).\(finalContainer)"

        let downloadItem = DownloadItem(
            id: itemID,
            item: item,
            fileName: fileName,
            status: .queued,
            progress: 0,
            bytesDownloaded: 0,
            totalBytes: 0,
            dateAdded: Date(),
            dateCompleted: nil,
            errorMessage: nil,
            estimatedTimeRemaining: nil,
            statusDetail: nil,
            group: group
        )

        downloads[itemID] = downloadItem
        if !downloadQueue.contains(itemID) {
            downloadQueue.append(itemID)
        }

        // Cache poster artwork for offline browsing (both UI card size and high-res detail size)
        let primaryTag = item.imageTags?["Primary"]
        if let cardPosterURL = client.itemImageURL(
            itemID: itemID,
            parameters: .poster(tag: primaryTag)
        ) {
            SDWebImageManager.shared.loadImage(
                with: cardPosterURL,
                options: [.continueInBackground, .highPriority],
                progress: nil
            ) { [weak self] downloadedImage, _, _, _, _, _ in
                guard let self, let downloadedImage else { return }
                Task { @MainActor in
                    if let thumbData = downloadedImage.liveActivityThumbnailData() {
                        self.cachedPosterThumbnails[cardPosterURL.absoluteString] = thumbData
                        self.updateLiveActivity(force: true)
                    }
                }
            }
        }

        if let detailPosterURL = client.itemImageURL(
            itemID: itemID,
            parameters: .detailPoster(tag: primaryTag)
        ) {
            SDWebImageManager.shared.loadImage(
                with: detailPosterURL,
                options: [.continueInBackground, .lowPriority],
                progress: nil
            ) { _, _, _, _, _, _ in }
        }

        // Cache group poster artwork for offline browsing if grouped
        if let groupPosterURL = group?.posterURL(client: client) {
            SDWebImageManager.shared.loadImage(
                with: groupPosterURL,
                options: [.continueInBackground, .lowPriority],
                progress: nil
            ) { _, _, _, _, _, _ in }
        }
    }
}

// MARK: - Queue Processing (Strictly Sequential)

extension DownloadManager {
    func processQueue() {
        if let activeID = activeDownloadingID {
            if let task = activeTasks[activeID], task.state == .running {
                return
            } else if activeTasks[activeID] == nil {
                activeDownloadingID = nil
            }
        }

        guard activeDownloadingID == nil else { return }

        // Reconcile queue if empty but queued items exist in downloads
        if downloadQueue.isEmpty {
            let queuedIDs = downloads.values
                .filter { $0.status == .queued }
                .sorted { a, b in
                    if let sA = a.item.parentIndexNumber, let sB = b.item.parentIndexNumber,
                       let eA = a.item.indexNumber, let eB = b.item.indexNumber,
                       (a.item.seriesID == b.item.seriesID || a.item.seriesName == b.item.seriesName) {
                        if sA != sB { return sA < sB }
                        return eA < eB
                    }
                    return a.dateAdded < b.dateAdded
                }
                .map(\.id)
            downloadQueue.append(contentsOf: queuedIDs)
        }

        while !downloadQueue.isEmpty {
            let nextID = downloadQueue.removeFirst()
            guard var item = downloads[nextID] else { continue }

            guard item.status == .queued else { continue }

            // Clean up any stale or incomplete file with this name before starting fresh
            storage.deleteFile(fileName: item.fileName)

            if let resumeData = resumeDataMap[nextID] {
                let task = session.downloadTask(withResumeData: resumeData)
                task.taskDescription = nextID
                activeTasks[nextID] = task
                activeDownloadingID = nextID
                resumeDataMap.removeValue(forKey: nextID)

                item.status = .downloading
                item.errorMessage = nil
                downloads[nextID] = item
                saveIndex()
                task.resume()
                AppLogger.info("Resumed sequential download for '\(item.title)' (ID: \(nextID))")
                updateLiveActivity(force: true)
                return
            } else {
                guard let client = getOrRestoreClient() else {
                    AppLogger.warning("Cannot start queued download for \(nextID): No JellyfinClient available")
                    downloadQueue.insert(nextID, at: 0)
                    return
                }

                let downloadPath = Paths.getDownload(itemID: nextID)
                guard let downloadURL = client.url(with: downloadPath, queryAPIKey: true) else {
                    item.status = .failed
                    item.errorMessage = "Failed to construct download URL."
                    downloads[nextID] = item
                    saveIndex()
                    AppLogger.error("Failed to construct download URL for queued item \(nextID)")
                    continue
                }

                var request = URLRequest(url: downloadURL)
                request.setValue(JellyfinAuthorization.header(for: client), forHTTPHeaderField: "Authorization")

                let task = session.downloadTask(with: request)
                task.taskDescription = nextID
                activeTasks[nextID] = task
                activeDownloadingID = nextID

                item.status = .downloading
                item.errorMessage = nil
                downloads[nextID] = item
                saveIndex()
                task.resume()
                AppLogger.info("Started sequential download for '\(item.title)' (ID: \(nextID))")
                updateLiveActivity(force: true)
                return
            }
        }
    }

    public func resumeDownload(id: String, client: JellyfinClient? = nil) {
        if let client {
            self.client = client
        }
        guard var item = downloads[id] else { return }
        guard item.status != .completed else { return }
        guard item.status != .downloading, item.status != .converting, item.status != .finalizing else { return }

        item.status = .queued
        item.errorMessage = nil
        downloads[id] = item
        if !downloadQueue.contains(id) {
            downloadQueue.append(id)
        }
        saveIndex()
        processQueue()
        updateLiveActivity(force: true)
        AppLogger.info("Enqueued resumed download for item \(id)")
    }
}

// MARK: - Cancelling & Deleting

extension DownloadManager {
    public func cancelDownloads(ids: [String]) {
        let idSet = Set(ids)
        for id in idSet {
            if let task = activeTasks[id] {
                task.cancel()
                activeTasks.removeValue(forKey: id)
            }
            if activeDownloadingID == id {
                activeDownloadingID = nil
            }
            resumeDataMap.removeValue(forKey: id)
            retryAttempts.removeValue(forKey: id)
            progressTracker.clear(itemID: id)
            if let item = downloads[id] {
                storage.deleteFile(fileName: item.fileName)
            }
            storage.deleteAllFiles(for: id)
            downloads.removeValue(forKey: id)
        }
        downloadQueue.removeAll { idSet.contains($0) }
        saveIndex()
        processQueue()

        if activeDownloads.isEmpty {
            DownloadActivityCoordinator.shared.cancel()
        } else {
            updateLiveActivity(force: true)
        }

        AppLogger.info("Cancelled \(idSet.count) download(s)")
    }

    public func cancelDownload(id: String) {
        cancelDownloads(ids: [id])
    }

    public func deleteDownloads(ids: [String]) {
        let idSet = Set(ids)
        for id in idSet {
            if let item = downloads[id] {
                storage.deleteFile(fileName: item.fileName)
            }
            storage.deleteAllFiles(for: id)
        }
        cancelDownloads(ids: ids)
        AppLogger.info("Deleted \(idSet.count) download(s) and local files")
    }

    public func deleteDownload(id: String) {
        deleteDownloads(ids: [id])
    }

    public func deleteAllDownloads() {
        for (_, task) in activeTasks {
            task.cancel()
        }
        activeTasks.removeAll()
        activeDownloadingID = nil
        downloadQueue.removeAll()
        resumeDataMap.removeAll()
        retryAttempts.removeAll()
        progressTracker.clearAll()

        for (_, item) in downloads {
            storage.deleteFile(fileName: item.fileName)
            storage.deleteAllFiles(for: item.id)
        }

        downloads.removeAll()
        saveIndex()
        DownloadActivityCoordinator.shared.cancel()
        AppLogger.info("Deleted all downloads and files")
    }
}
