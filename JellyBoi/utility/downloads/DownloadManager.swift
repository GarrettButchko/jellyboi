//
//  DownloadManager.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 10/8/26.
//

import Foundation
import Observation
import Get
import JellyfinAPI
import LoggingKit
import SDWebImage
import AVFoundation
import UIKit
import ImageIO

@Observable
@MainActor
public final class DownloadManager: NSObject {
    public static let shared = DownloadManager()

    public private(set) var downloads: [String: DownloadItem] = [:]

    public var client: JellyfinClient? {
        didSet {
            if client != nil {
                processQueue()
            }
        }
    }

    @ObservationIgnored
    private let storage = DownloadStorage()
    @ObservationIgnored
    private let progressTracker = DownloadProgressTracker()

    @ObservationIgnored
    private var downloadQueue: [String] = []
    @ObservationIgnored
    private var activeDownloadingID: String?
    @ObservationIgnored
    private var activeTasks: [String: URLSessionDownloadTask] = [:]
    @ObservationIgnored
    private var resumeDataMap: [String: Data] = [:]
    @ObservationIgnored
    private var retryAttempts: [String: Int] = [:]
    @ObservationIgnored
    private var session: URLSession!
    @ObservationIgnored
    private var cachedPosterThumbnails: [String: Data] = [:]

    public var downloadsDirectory: URL {
        storage.downloadsDirectory
    }

    public override init() {
        super.init()
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        config.timeoutIntervalForResource = 3600 * 6 // 6 hours max for large movies
        config.timeoutIntervalForRequest = 180 // 3 minutes timeout for individual chunks
        let delegateQueue = OperationQueue()
        delegateQueue.name = "com.jellyboi.downloadQueue"
        delegateQueue.maxConcurrentOperationCount = 1
        self.session = URLSession(configuration: config, delegate: self, delegateQueue: delegateQueue)

        let loaded = storage.loadIndex()
        self.downloads = loaded.items
        self.downloadQueue = loaded.queue
        let validFileNames = Set(loaded.items.values.map(\.fileName))
        storage.cleanupOrphanedFiles(validFileNames: validFileNames)
        if loaded.didHeal {
            saveIndex()
        }

        if client != nil {
            processQueue()
        }

        NotificationCenter.default.addObserver(
            forName: .mediaProgressUpdated,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let itemID = notification.object as? String,
                  let positionTicks = notification.userInfo?["positionTicks"] as? Int else { return }
            let totalTicks = notification.userInfo?["durationTicks"] as? Int
            MainActor.assumeIsolated {
                self.updateProgress(for: itemID, positionTicks: positionTicks, totalTicks: totalTicks)
            }
        }

        NotificationCenter.default.addObserver(
            forName: .mediaProgressReset,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let itemID = notification.object as? String else { return }
            MainActor.assumeIsolated {
                self.clearProgress(for: itemID)
            }
        }

        NotificationCenter.default.addObserver(
            forName: .mediaFavoriteToggled,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let itemID = notification.object as? String,
                  let isFavorite = notification.userInfo?["isFavorite"] as? Bool else { return }
            MainActor.assumeIsolated {
                self.updateFavorite(for: itemID, isFavorite: isFavorite)
            }
        }
    }

    // MARK: - Playback Progress & Metadata Sync

    public func updateProgress(for itemID: String, positionTicks: Int, totalTicks: Int?) {
        guard var downloadItem = downloads[itemID] else { return }
        downloadItem.item.updateProgress(positionTicks: positionTicks, totalTicks: totalTicks)
        downloads[itemID] = downloadItem
        saveIndex()
    }

    public func clearProgress(for itemID: String) {
        guard var downloadItem = downloads[itemID] else { return }
        downloadItem.item.clearProgress()
        downloads[itemID] = downloadItem
        saveIndex()
    }

    public func updateFavorite(for itemID: String, isFavorite: Bool) {
        guard var downloadItem = downloads[itemID] else { return }
        downloadItem.item.setFavorite(isFavorite)
        downloads[itemID] = downloadItem
        saveIndex()
    }

    // MARK: - Query State

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

    // MARK: - Categorized Completed Media

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

    public func isLocallyPlayable(id: String) -> Bool {
        guard let record = downloads[id], record.status == .completed else { return false }
        return storage.isLocallyPlayable(fileName: record.fileName)
    }

    public func playableLocalFileURL(for id: String) -> URL? {
        #if DEBUG
        if DebugSettings.shared.forceStreamFallback { return nil }
        #endif
        guard isLocallyPlayable(id: id) else { return nil }
        return localFileURL(for: id)
    }

    // MARK: - Actions

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
            AppLogger.warning("Cannot download item without ID", tag: "DownloadManager")
            return
        }

        if let existing = downloads[itemID], existing.status == .completed, localFileURL(for: itemID) != nil {
            AppLogger.info("Item '\(item.name ?? itemID)' is already downloaded", tag: "DownloadManager")
            return
        }

        if let existing = downloads[itemID], existing.status == .downloading || existing.status == .converting || existing.status == .finalizing || existing.status == .queued {
            AppLogger.info("Item '\(item.name ?? itemID)' is already downloading or queued", tag: "DownloadManager")
            return
        }

        let container = item.container?.lowercased() ?? "mp4"
        let safeContainer = container.isEmpty ? "mp4" : container
        let isNativePlayable = safeContainer == "mp4" || safeContainer == "m4v" || safeContainer == "mov"
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

    // MARK: - Queue Processing (Strictly Sequential)

    private func processQueue() {
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
                AppLogger.info("Resumed sequential download for '\(item.title)' (ID: \(nextID))", tag: "DownloadManager")
                updateLiveActivity(force: true)
                return
            } else {
                guard let client = self.client else {
                    AppLogger.warning("Cannot start queued download for \(nextID): No JellyfinClient available", tag: "DownloadManager")
                    downloadQueue.insert(nextID, at: 0)
                    return
                }

                let downloadPath = Paths.getDownload(itemID: nextID)
                guard let downloadURL = client.url(with: downloadPath, queryAPIKey: true) else {
                    item.status = .failed
                    item.errorMessage = "Failed to construct download URL."
                    downloads[nextID] = item
                    saveIndex()
                    AppLogger.error("Failed to construct download URL for queued item \(nextID)", tag: "DownloadManager")
                    continue
                }

                var request = URLRequest(url: downloadURL)
                request.setValue(authorizationHeader(for: client), forHTTPHeaderField: "Authorization")

                let task = session.downloadTask(with: request)
                task.taskDescription = nextID
                activeTasks[nextID] = task
                activeDownloadingID = nextID

                item.status = .downloading
                item.errorMessage = nil
                downloads[nextID] = item
                saveIndex()
                task.resume()
                AppLogger.info("Started sequential download for '\(item.title)' (ID: \(nextID))", tag: "DownloadManager")
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
        AppLogger.info("Enqueued resumed download for item \(id)", tag: "DownloadManager")
    }

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

        AppLogger.info("Cancelled \(idSet.count) download(s)", tag: "DownloadManager")
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
        AppLogger.info("Deleted \(idSet.count) download(s) and local files", tag: "DownloadManager")
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
        AppLogger.info("Deleted all downloads and files", tag: "DownloadManager")
    }

    // MARK: - Internal Session & Progress Handling

    private func handleProgress(
        itemID: String,
        bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpected: Int64
    ) {
        let now = Date().timeIntervalSince1970
        guard !progressTracker.shouldThrottleDownload(
            itemID: itemID,
            now: now,
            totalBytesWritten: totalBytesWritten,
            totalBytesExpected: totalBytesExpected
        ) else { return }

        guard var item = downloads[itemID] else { return }
        item.status = .downloading
        item.bytesDownloaded = totalBytesWritten
        if totalBytesExpected > 0 {
            item.totalBytes = totalBytesExpected
        }

        let calculation = progressTracker.calculateDownloadProgress(
            itemID: itemID,
            now: now,
            totalBytesWritten: totalBytesWritten,
            totalBytesExpected: totalBytesExpected
        )

        if totalBytesExpected > 0 {
            item.progress = calculation.progress
        }
        if let eta = calculation.eta {
            item.estimatedTimeRemaining = eta
        }

        downloads[itemID] = item
        updateLiveActivity()
    }

    private func handleCompleted(itemID: String, tempLocation: URL) {
        guard var item = downloads[itemID] else { return }
        let destinationURL = storage.downloadsDirectory.appendingPathComponent(item.fileName)

        let rawContainer = item.item.container?.lowercased() ?? ""
        let isRawNative = rawContainer == "mp4" || rawContainer == "m4v" || rawContainer == "mov"
        let itemTitle = item.title
        let itemBytesDownloaded = item.bytesDownloaded
        let targetAspect = item.item.mediaStreams?.first(where: { $0.type == .video })?.aspectRatio
            ?? item.item.mediaSources?.compactMap({ $0.mediaStreams }).flatMap({ $0 }).first(where: { $0.type == .video })?.aspectRatio
            ?? item.item.aspectRatio

        item.status = isRawNative ? .finalizing : .converting
        item.progress = min(max(item.progress, 0.0), 1.0)
        item.statusDetail = isRawNative ? "Finalizing..." : "Converting video..."
        item.estimatedTimeRemaining = nil
        downloads[itemID] = item

        Task.detached(priority: .utility) {
            do {
                let fileSize = try await DownloadPostProcessor.processDownloadedFile(
                    itemID: itemID,
                    itemTitle: itemTitle,
                    tempLocation: tempLocation,
                    destinationURL: destinationURL,
                    rawContainer: rawContainer,
                    targetAspect: targetAspect,
                    itemBytesDownloaded: itemBytesDownloaded,
                    onStateChange: { status, detail in
                        Task { @MainActor in
                            DownloadManager.shared.updateState(itemID: itemID, status: status, detail: detail)
                        }
                    },
                    onProgress: { progress in
                        Task { @MainActor in
                            DownloadManager.shared.updateFinalizingProgress(itemID: itemID, progress: progress)
                        }
                    }
                )

                await MainActor.run {
                    DownloadManager.shared.finishItemCompleted(itemID: itemID, fileSize: fileSize)
                }
            } catch {
                try? FileManager.default.removeItem(at: tempLocation)
                try? FileManager.default.removeItem(at: destinationURL)
                await MainActor.run {
                    DownloadManager.shared.finishItemFailed(itemID: itemID, error: error)
                }
            }
        }
    }

    private func updateState(itemID: String, status: DownloadStatus, detail: String?) {
        guard var cur = downloads[itemID] else { return }
        cur.status = status
        cur.statusDetail = detail
        if status == .converting {
            cur.estimatedTimeRemaining = nil
            progressTracker.startConversion(itemID: itemID)
        }
        downloads[itemID] = cur
        updateLiveActivity()
    }

    private func updateFinalizingProgress(itemID: String, progress: Double) {
        guard var item = downloads[itemID], item.status == .converting || item.status == .finalizing else { return }

        let result = progressTracker.calculateConversionProgress(
            itemID: itemID,
            progress: progress,
            previousProgress: item.progress,
            previousETA: item.estimatedTimeRemaining
        )

        if result.shouldUpdate {
            item.progress = result.progress
            item.status = .converting
            item.statusDetail = "Converting video..."
            if let eta = result.eta {
                item.estimatedTimeRemaining = eta
            }
            downloads[itemID] = item
            updateLiveActivity()
        }
    }

    private func finishItemCompleted(itemID: String, fileSize: Int64) {
        guard var item = downloads[itemID] else { return }
        item.status = .completed
        item.statusDetail = nil
        item.progress = 1.0
        item.bytesDownloaded = fileSize
        item.totalBytes = fileSize
        item.estimatedTimeRemaining = nil
        item.dateCompleted = Date()
        item.errorMessage = nil

        downloads[itemID] = item
        activeTasks.removeValue(forKey: itemID)
        resumeDataMap.removeValue(forKey: itemID)
        retryAttempts.removeValue(forKey: itemID)
        progressTracker.clear(itemID: itemID)
        if activeDownloadingID == itemID {
            activeDownloadingID = nil
        }
        saveIndex()

        let remainingActive = activeDownloads
        let isLastItem = remainingActive.isEmpty
        DownloadNotificationManager.shared.notifyItemCompleted(
            title: item.title,
            seriesName: item.item.seriesName,
            isLastItem: isLastItem,
            remainingCount: remainingActive.count
        )

        if isLastItem {
            DownloadActivityCoordinator.shared.finishAll(finalTitle: item.title)
        } else {
            updateLiveActivity(force: true)
        }

        AppLogger.success("Download and processing completed successfully for '\(item.title)'", tag: "DownloadManager")
        processQueue()
    }

    private func finishItemFailed(itemID: String, error: Error) {
        guard var item = downloads[itemID] else { return }
        item.status = .failed
        item.statusDetail = nil
        item.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        item.estimatedTimeRemaining = nil
        downloads[itemID] = item
        activeTasks.removeValue(forKey: itemID)
        progressTracker.clear(itemID: itemID)
        if activeDownloadingID == itemID {
            activeDownloadingID = nil
        }
        storage.deleteFile(fileName: item.fileName)
        storage.deleteAllFiles(for: itemID)
        saveIndex()

        DownloadNotificationManager.shared.notifyItemFailed(
            title: item.title,
            error: item.errorMessage
        )
        updateLiveActivity(force: true)

        AppLogger.error("Failed to finalize downloaded file for '\(item.title)': \(error.localizedDescription)", error, tag: "DownloadManager")
        processQueue()
    }

    private func handleError(itemID: String, error: Error, resumeData: Data?) {
        guard var item = downloads[itemID] else { return }

        // Do not overwrite an already completed download
        if item.status == .completed {
            if let resumeData {
                resumeDataMap[itemID] = resumeData
            }
            return
        }

        let nsError = error as NSError
        let isCancelled = (error as? URLError)?.code == .cancelled || (nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled)

        if isCancelled {
            if let resumeData {
                resumeDataMap[itemID] = resumeData
            }
            activeTasks.removeValue(forKey: itemID)
            progressTracker.clear(itemID: itemID)
            if activeDownloadingID == itemID {
                activeDownloadingID = nil
            }
            processQueue()
            return
        }

        if let resumeData {
            resumeDataMap[itemID] = resumeData
        }

        activeTasks.removeValue(forKey: itemID)
        progressTracker.clear(itemID: itemID)
        if activeDownloadingID == itemID {
            activeDownloadingID = nil
        }

        // Automatic retry for transient network dropouts (e.g. -1005 Network Connection Lost, -1001 Timed Out)
        let isTransientNetworkError: Bool = {
            guard nsError.domain == NSURLErrorDomain else { return false }
            return [
                NSURLErrorNetworkConnectionLost,
                NSURLErrorTimedOut,
                NSURLErrorCannotConnectToHost,
                NSURLErrorNotConnectedToInternet,
                NSURLErrorDNSLookupFailed
            ].contains(nsError.code)
        }()

        let attempts = retryAttempts[itemID, default: 0]
        if isTransientNetworkError && attempts < 5 {
            retryAttempts[itemID] = attempts + 1
            item.status = .downloading
            item.statusDetail = "Reconnecting (attempt \(attempts + 1)/5)..."
            downloads[itemID] = item
            saveIndex()

            AppLogger.warning("Transient network error for '\(item.title)' (\(error.localizedDescription)). Retrying with resumeData in \(attempts + 1)s (attempt \(attempts + 1)/5)...", tag: "DownloadManager")

            if !downloadQueue.contains(itemID) {
                downloadQueue.insert(itemID, at: 0)
            }

            let delay = Double(min(attempts + 1, 10))
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard let self, self.activeDownloadingID == nil else { return }
                self.processQueue()
            }
            return
        }

        retryAttempts.removeValue(forKey: itemID)
        item.status = .failed
        item.errorMessage = error.localizedDescription
        item.estimatedTimeRemaining = nil
        item.statusDetail = nil
        downloads[itemID] = item
        storage.deleteFile(fileName: item.fileName)
        storage.deleteAllFiles(for: itemID)
        saveIndex()

        DownloadNotificationManager.shared.notifyItemFailed(
            title: item.title,
            error: item.errorMessage
        )
        updateLiveActivity(force: true)

        AppLogger.error("Download failed for '\(item.title)': \(item.errorMessage ?? "")", tag: "DownloadManager")
        processQueue()
    }

    // MARK: - Live Activity Coordination

    private func updateLiveActivity(force: Bool = false) {
        let active = activeDownloads
        guard !active.isEmpty else { return }
        var presentation = currentPresentation
        if presentation.isSingleElement, let posterURL = presentation.posterURL {
            let urlString = posterURL.absoluteString
            if let cached = cachedPosterThumbnails[urlString], cached.count <= 2200 {
                presentation = presentation.with(posterImageData: cached)
            } else {
                let cacheKey = SDWebImageManager.shared.cacheKey(for: posterURL) ?? urlString
                if let image = SDImageCache.shared.imageFromMemoryCache(forKey: cacheKey) ?? SDImageCache.shared.imageFromDiskCache(forKey: cacheKey),
                   let thumbData = image.liveActivityThumbnailData() {
                    cachedPosterThumbnails[urlString] = thumbData
                    presentation = presentation.with(posterImageData: thumbData)
                } else {
                    SDWebImageManager.shared.loadImage(
                        with: posterURL,
                        options: [.continueInBackground, .highPriority],
                        progress: nil
                    ) { [weak self] downloadedImage, _, _, _, _, _ in
                        guard let self, let downloadedImage else { return }
                        Task { @MainActor in
                            guard let thumbData = downloadedImage.liveActivityThumbnailData() else { return }
                            self.cachedPosterThumbnails[urlString] = thumbData
                            var updated = self.currentPresentation
                            updated = updated.with(posterImageData: thumbData)
                            DownloadActivityCoordinator.shared.update(presentation: updated, force: true)
                        }
                    }
                }
            }
        }
        DownloadActivityCoordinator.shared.update(presentation: presentation, force: force)
    }

    // MARK: - Persistence

    private func saveIndex() {
        storage.saveIndex(items: Array(downloads.values))
    }

    private func authorizationHeader(for client: JellyfinClient) -> String {
        var rawFields = [
            "DeviceId": client.configuration.deviceID,
            "Device": client.configuration.deviceName,
            "Client": client.configuration.client,
            "Version": client.configuration.version,
        ]
        if let token = client.configuration.accessToken {
            rawFields["Token"] = token
        }
        let fields = rawFields.map { "\($0.key)=\"\($0.value)\"" }.joined(separator: ", ")
        return "MediaBrowser \(fields)"
    }
}

// MARK: - URLSessionDownloadDelegate

extension DownloadManager: URLSessionDownloadDelegate {
    public nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let itemID = downloadTask.taskDescription else { return }
        Task { @MainActor in
            DownloadManager.shared.handleProgress(
                itemID: itemID,
                bytesWritten: bytesWritten,
                totalBytesWritten: totalBytesWritten,
                totalBytesExpected: totalBytesExpectedToWrite
            )
        }
    }

    public nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let itemID = downloadTask.taskDescription else { return }
        // Copy to temporary location before system removes it
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.copyItem(at: location, to: tempURL)

        Task { @MainActor in
            DownloadManager.shared.handleCompleted(itemID: itemID, tempLocation: tempURL)
        }
    }

    public nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let itemID = task.taskDescription else { return }
        guard let error else {
            // Task finished successfully! didFinishDownloadingTo handled file completion.
            return
        }
        let resumeData = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data

        Task { @MainActor in
            DownloadManager.shared.handleError(itemID: itemID, error: error, resumeData: resumeData)
        }
    }
}

// MARK: - UIImage Live Activity Thumbnail

extension UIImage {
    func liveActivityThumbnailData(maxDimension: CGFloat = 56) -> Data? {
        guard size.width > 0 && size.height > 0 else { return nil }

        let aspect = size.width / size.height
        let targetSize: CGSize
        if aspect > 1.0 {
            // Landscape (e.g. 16:9 episode thumbnail): preserve aspect ratio
            let targetWidth = min(maxDimension, size.width)
            let targetHeight = max(1, round(targetWidth / aspect))
            targetSize = CGSize(width: targetWidth, height: targetHeight)
        } else {
            // Portrait (e.g. 2:3 poster): preserve aspect ratio
            let targetHeight = min(maxDimension, size.height)
            let targetWidth = max(1, round(targetHeight * aspect))
            targetSize = CGSize(width: targetWidth, height: targetHeight)
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let resized = renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: targetSize))
        }

        for quality in [0.6, 0.45, 0.3, 0.15] {
            if let data = resized.jpegData(compressionQuality: quality), data.count <= 2000 {
                return data
            }
        }
        return resized.jpegData(compressionQuality: 0.15)
    }
}
