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

public enum DownloadStatus: String, Codable, Sendable {
    case queued
    case downloading
    case paused
    case completed
    case failed
}

public struct DownloadItem: Codable, Identifiable, Sendable, Equatable {
    public let id: String
    public let item: BaseItemDto
    public let fileName: String
    public var status: DownloadStatus
    public var progress: Double
    public var bytesDownloaded: Int64
    public var totalBytes: Int64
    public let dateAdded: Date
    public var dateCompleted: Date?
    public var errorMessage: String?

    public static func == (lhs: DownloadItem, rhs: DownloadItem) -> Bool {
        lhs.id == rhs.id &&
        lhs.status == rhs.status &&
        lhs.progress == rhs.progress &&
        lhs.bytesDownloaded == rhs.bytesDownloaded &&
        lhs.totalBytes == rhs.totalBytes &&
        lhs.errorMessage == rhs.errorMessage
    }

    public var title: String {
        if item.type == .episode {
            var parts: [String] = []
            if let series = item.seriesName {
                parts.append(series)
            }
            if let s = item.parentIndexNumber, let e = item.indexNumber {
                parts.append("S\(s):E\(e)")
            }
            if let name = item.name, !name.isEmpty {
                parts.append(name)
            }
            return parts.isEmpty ? (item.name ?? "Episode") : parts.joined(separator: " - ")
        }
        return item.name ?? "Video"
    }

    public var formattedProgress: String {
        if totalBytes > 0 {
            let downloaded = ByteCountFormatter.string(fromByteCount: bytesDownloaded, countStyle: .file)
            let total = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
            return "\(downloaded) / \(total)"
        } else if bytesDownloaded > 0 {
            return ByteCountFormatter.string(fromByteCount: bytesDownloaded, countStyle: .file)
        } else {
            return "0 KB"
        }
    }

    public var formattedPercentage: String {
        let percent = Int(progress * 100)
        return "\(percent)%"
    }
}

@Observable
@MainActor
public final class DownloadManager: NSObject {
    public static let shared = DownloadManager()

    public private(set) var downloads: [String: DownloadItem] = [:]

    @ObservationIgnored
    private var activeTasks: [String: URLSessionDownloadTask] = [:]
    @ObservationIgnored
    private var resumeDataMap: [String: Data] = [:]
    @ObservationIgnored
    private var session: URLSession!
    @ObservationIgnored
    private var lastProgressUpdateTime: [String: TimeInterval] = [:]

    private let fileManager = FileManager.default
    private let indexFileName = "downloads_index.json"

    public var downloadsDirectory: URL {
        let urls = fileManager.urls(for: .documentDirectory, in: .userDomainMask)
        let dir = urls[0].appendingPathComponent("Downloads", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            var mutableDir = dir
            try? mutableDir.setResourceValues(resourceValues)
        }
        return dir
    }

    private var indexFileURL: URL {
        downloadsDirectory.appendingPathComponent(indexFileName)
    }

    public override init() {
        super.init()
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        config.timeoutIntervalForResource = 3600 * 6 // 6 hours max for large movies
        let delegateQueue = OperationQueue()
        delegateQueue.name = "com.jellyboi.downloadQueue"
        delegateQueue.maxConcurrentOperationCount = 2
        self.session = URLSession(configuration: config, delegate: self, delegateQueue: delegateQueue)

        loadIndex()
    }

    // MARK: - Query State

    public var downloadList: [DownloadItem] {
        Array(downloads.values).sorted { $0.dateAdded > $1.dateAdded }
    }

    public var activeDownloads: [DownloadItem] {
        downloadList.filter { $0.status == .downloading || $0.status == .queued }
    }

    public var completedDownloads: [DownloadItem] {
        downloadList.filter { item in
            if item.status == .completed { return true }
            let fileURL = downloadsDirectory.appendingPathComponent(item.fileName)
            return fileManager.fileExists(atPath: fileURL.path)
        }
    }

    public var hasActiveDownloads: Bool {
        !activeDownloads.isEmpty
    }

    public var hasCompletedDownloads: Bool {
        !completedDownloads.isEmpty
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
        guard let item = downloads[id] else { return false }
        if item.status == .completed { return true }
        let fileURL = downloadsDirectory.appendingPathComponent(item.fileName)
        return fileManager.fileExists(atPath: fileURL.path)
    }

    public func isDownloading(id: String) -> Bool {
        guard let item = downloads[id] else { return false }
        return item.status == .downloading || item.status == .queued
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
        let fileURL = downloadsDirectory.appendingPathComponent(record.fileName)
        if fileManager.fileExists(atPath: fileURL.path) {
            return fileURL
        }
        return nil
    }

    // MARK: - Actions

    public func startDownload(item: BaseItemDto, client: JellyfinClient) {
        guard let itemID = item.id else {
            AppLogger.warning("Cannot download item without ID", tag: "DownloadManager")
            return
        }

        if let existing = downloads[itemID], existing.status == .completed, localFileURL(for: itemID) != nil {
            AppLogger.info("Item '\(item.name ?? itemID)' is already downloaded", tag: "DownloadManager")
            return
        }

        let container = item.container?.lowercased() ?? "mp4"
        let safeContainer = container.isEmpty ? "mp4" : container
        let fileName = "\(itemID).\(safeContainer)"

        var downloadItem = DownloadItem(
            id: itemID,
            item: item,
            fileName: fileName,
            status: .queued,
            progress: 0,
            bytesDownloaded: 0,
            totalBytes: 0,
            dateAdded: Date(),
            dateCompleted: nil,
            errorMessage: nil
        )

        downloads[itemID] = downloadItem
        saveIndex()

        // Cache poster artwork for offline browsing
        if let posterURL = client.url(with: Paths.getItemImage(
            itemID: itemID,
            imageType: "Primary",
            parameters: .init(maxWidth: 600, quality: 90)
        )) {
            SDWebImageManager.shared.loadImage(
                with: posterURL,
                options: [.continueInBackground, .highPriority],
                progress: nil
            ) { _, _, _, _, _, _ in }
        }

        // Start download task
        let downloadPath = Paths.getDownload(itemID: itemID)
        guard let downloadURL = client.url(with: downloadPath, queryAPIKey: true) else {
            downloadItem.status = .failed
            downloadItem.errorMessage = "Failed to construct download URL."
            downloads[itemID] = downloadItem
            saveIndex()
            AppLogger.error("Failed to construct download URL for item \(itemID)", tag: "DownloadManager")
            return
        }

        var request = URLRequest(url: downloadURL)
        request.setValue(authorizationHeader(for: client), forHTTPHeaderField: "Authorization")

        let task = session.downloadTask(with: request)
        task.taskDescription = itemID
        activeTasks[itemID] = task
        task.resume()

        downloadItem.status = .downloading
        downloads[itemID] = downloadItem
        saveIndex()

        AppLogger.info("Started download for '\(downloadItem.title)' (ID: \(itemID))", tag: "DownloadManager")
    }

    public func pauseDownload(id: String) {
        guard let task = activeTasks[id] else {
            if var item = downloads[id], item.status == .downloading {
                item.status = .paused
                downloads[id] = item
                saveIndex()
            }
            return
        }

        task.cancel(byProducingResumeData: { [weak self] data in
            guard let self, let data else { return }
            Task { @MainActor in
                self.resumeDataMap[id] = data
                if var item = self.downloads[id] {
                    item.status = .paused
                    self.downloads[id] = item
                    self.saveIndex()
                }
                self.activeTasks.removeValue(forKey: id)
                AppLogger.info("Paused download for item \(id) with resume data", tag: "DownloadManager")
            }
        })
    }

    public func resumeDownload(id: String, client: JellyfinClient? = nil) {
        guard var item = downloads[id] else { return }

        if let resumeData = resumeDataMap[id] {
            let task = session.downloadTask(withResumeData: resumeData)
            task.taskDescription = id
            activeTasks[id] = task
            task.resume()
            resumeDataMap.removeValue(forKey: id)

            item.status = .downloading
            item.errorMessage = nil
            downloads[id] = item
            saveIndex()
            AppLogger.info("Resumed download from resume data for item \(id)", tag: "DownloadManager")
        } else if let client {
            startDownload(item: item.item, client: client)
        } else {
            AppLogger.warning("Cannot resume download without client or resume data", tag: "DownloadManager")
        }
    }

    public func cancelDownload(id: String) {
        if let task = activeTasks[id] {
            task.cancel()
            activeTasks.removeValue(forKey: id)
        }
        resumeDataMap.removeValue(forKey: id)
        downloads.removeValue(forKey: id)
        saveIndex()
        AppLogger.info("Cancelled download for item \(id)", tag: "DownloadManager")
    }

    public func deleteDownload(id: String) {
        cancelDownload(id: id)

        if let item = downloads[id] {
            let fileURL = downloadsDirectory.appendingPathComponent(item.fileName)
            try? fileManager.removeItem(at: fileURL)
        }

        downloads.removeValue(forKey: id)
        saveIndex()
        AppLogger.info("Deleted download and local file for item \(id)", tag: "DownloadManager")
    }

    public func deleteAllDownloads() {
        for (id, task) in activeTasks {
            task.cancel()
            AppLogger.info("Cancelled active task for \(id)", tag: "DownloadManager")
        }
        activeTasks.removeAll()
        resumeDataMap.removeAll()

        for (_, item) in downloads {
            let fileURL = downloadsDirectory.appendingPathComponent(item.fileName)
            try? fileManager.removeItem(at: fileURL)
        }

        downloads.removeAll()
        saveIndex()
        AppLogger.info("Deleted all downloads and files", tag: "DownloadManager")
    }

    // MARK: - Internal Session Handling

    private func handleProgress(
        itemID: String,
        bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpected: Int64
    ) {
        let now = Date().timeIntervalSince1970
        let lastUpdate = lastProgressUpdateTime[itemID] ?? 0
        // Throttle progress updates to at most once per 0.1s
        guard now - lastUpdate > 0.1 || totalBytesWritten >= totalBytesExpected else { return }
        lastProgressUpdateTime[itemID] = now

        guard var item = downloads[itemID] else { return }
        item.status = .downloading
        item.bytesDownloaded = totalBytesWritten
        if totalBytesExpected > 0 {
            item.totalBytes = totalBytesExpected
            item.progress = Double(totalBytesWritten) / Double(totalBytesExpected)
        }
        downloads[itemID] = item
    }

    private func handleCompleted(itemID: String, tempLocation: URL) {
        guard var item = downloads[itemID] else { return }
        let destinationURL = downloadsDirectory.appendingPathComponent(item.fileName)

        do {
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.moveItem(at: tempLocation, to: destinationURL)

            let attributes = try fileManager.attributesOfItem(atPath: destinationURL.path)
            let fileSize = attributes[.size] as? Int64 ?? item.bytesDownloaded

            item.status = .completed
            item.progress = 1.0
            item.bytesDownloaded = fileSize
            item.totalBytes = fileSize
            item.dateCompleted = Date()
            item.errorMessage = nil

            downloads[itemID] = item
            activeTasks.removeValue(forKey: itemID)
            resumeDataMap.removeValue(forKey: itemID)
            saveIndex()

            AppLogger.success("Download completed successfully for '\(item.title)'", tag: "DownloadManager")
        } catch {
            item.status = .failed
            item.errorMessage = "Failed to save file: \(error.localizedDescription)"
            downloads[itemID] = item
            activeTasks.removeValue(forKey: itemID)
            saveIndex()

            AppLogger.error("Failed to move downloaded file for '\(item.title)': \(error.localizedDescription)", error, tag: "DownloadManager")
        }
    }

    private func handleError(itemID: String, error: Error, resumeData: Data?) {
        guard var item = downloads[itemID] else { return }

        // Do not overwrite an already completed download
        if item.status == .completed { return }

        if let resumeData {
            resumeDataMap[itemID] = resumeData
        }

        activeTasks.removeValue(forKey: itemID)

        if let error = error as? URLError, error.code == .cancelled {
            // Task was intentionally cancelled or paused
            return
        }

        item.status = .failed
        item.errorMessage = error.localizedDescription
        downloads[itemID] = item
        saveIndex()

        AppLogger.error("Download failed for '\(item.title)': \(item.errorMessage ?? "")", tag: "DownloadManager")
    }

    // MARK: - Persistence

    private func saveIndex() {
        do {
            let data = try JSONEncoder().encode(Array(downloads.values))
            try data.write(to: indexFileURL, options: .atomic)
        } catch {
            AppLogger.error("Failed to save downloads index: \(error.localizedDescription)", error, tag: "DownloadManager")
        }
    }

    private func loadIndex() {
        guard fileManager.fileExists(atPath: indexFileURL.path) else { return }
        do {
            let data = try Data(contentsOf: indexFileURL)
            let items = try JSONDecoder().decode([DownloadItem].self, from: data)

            var loaded: [String: DownloadItem] = [:]
            var didHeal = false
            for var item in items {
                let fileURL = downloadsDirectory.appendingPathComponent(item.fileName)
                let fileExists = fileManager.fileExists(atPath: fileURL.path)

                if fileExists {
                    if item.status != .completed {
                        item.status = .completed
                        item.progress = 1.0
                        item.errorMessage = nil
                        didHeal = true
                    }
                    loaded[item.id] = item
                } else if item.status == .completed {
                    continue
                } else {
                    // Downloads interrupted by app termination become paused
                    item.status = .paused
                    loaded[item.id] = item
                }
            }
            self.downloads = loaded
            if didHeal {
                saveIndex()
            }
            AppLogger.info("Loaded \(loaded.count) downloads from index", tag: "DownloadManager")
        } catch {
            AppLogger.error("Failed to load downloads index: \(error.localizedDescription)", error, tag: "DownloadManager")
        }
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
