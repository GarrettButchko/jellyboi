//
//  DownloadStorage.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 10/15/26.
//

import Foundation
import JellyfinAPI
import LoggingKit

public final class DownloadStorage: @unchecked Sendable {
    private let fileManager = FileManager.default
    private let indexFileName = "downloads_index.json"

    public init() {}

    public static var downloadsDirectoryURL: URL {
        let urls = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let dir = urls[0].appendingPathComponent("Downloads", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            var mutableDir = dir
            try? mutableDir.setResourceValues(resourceValues)
        }
        return dir
    }

    public var downloadsDirectory: URL {
        Self.downloadsDirectoryURL
    }

    private var indexFileURL: URL {
        downloadsDirectory.appendingPathComponent(indexFileName)
    }

    public func localFileURL(for fileName: String) -> URL? {
        let fileURL = downloadsDirectory.appendingPathComponent(fileName)
        if fileManager.fileExists(atPath: fileURL.path) {
            return fileURL
        }
        return nil
    }

    public func fileExists(for fileName: String) -> Bool {
        let fileURL = downloadsDirectory.appendingPathComponent(fileName)
        return fileManager.fileExists(atPath: fileURL.path)
    }

    public func saveIndex(items: [DownloadItem]) {
        do {
            let data = try JSONEncoder().encode(items)
            try data.write(to: indexFileURL, options: .atomic)
        } catch {
            AppLogger.error("Failed to save downloads index: \(error.localizedDescription)", error)
        }
    }

    public func loadIndex() -> (items: [String: DownloadItem], queue: [String], didHeal: Bool) {
        guard fileManager.fileExists(atPath: indexFileURL.path) else {
            return ([:], [], false)
        }
        do {
            let data = try Data(contentsOf: indexFileURL)
            let items = try JSONDecoder().decode([DownloadItem].self, from: data)

            var loaded: [String: DownloadItem] = [:]
            var didHeal = false
            for var item in items {
                var fileURL = downloadsDirectory.appendingPathComponent(item.fileName)
                var fileExists = fileManager.fileExists(atPath: fileURL.path)

                // If previous version saved an .mkv file name, check if .mp4 exists or self-heal
                if !fileExists && item.fileName.hasSuffix(".mkv") {
                    let mp4Name = item.fileName.replacingOccurrences(of: ".mkv", with: ".mp4")
                    let mp4URL = downloadsDirectory.appendingPathComponent(mp4Name)
                    if fileManager.fileExists(atPath: mp4URL.path) {
                        item = DownloadItem(
                            id: item.id,
                            item: item.item,
                            fileName: mp4Name,
                            status: item.status,
                            progress: item.progress,
                            bytesDownloaded: item.bytesDownloaded,
                            totalBytes: item.totalBytes,
                            dateAdded: item.dateAdded,
                            dateCompleted: item.dateCompleted,
                            errorMessage: item.errorMessage,
                            estimatedTimeRemaining: item.estimatedTimeRemaining
                        )
                        fileURL = mp4URL
                        fileExists = true
                        didHeal = true
                    }
                }

                if item.status == .failed {
                    // A failed download must never be marked as completed or queued.
                    // Clean up any stray or corrupt file that may have been left behind.
                    if fileExists {
                        try? fileManager.removeItem(at: fileURL)
                    }
                    loaded[item.id] = item
                    continue
                }

                if item.status == .completed {
                    if fileExists {
                        loaded[item.id] = item
                    } else {
                        // Completed download whose file was removed from storage -> drop from index
                        didHeal = true
                    }
                    continue
                }

                // If it was downloading, converting, finalizing, or queued when app was closed:
                // Clean up any incomplete file on disk from the interrupted operation
                if fileExists {
                    try? fileManager.removeItem(at: fileURL)
                }
                item.status = .queued
                item.errorMessage = nil
                item.estimatedTimeRemaining = nil
                item.statusDetail = nil
                loaded[item.id] = item
                didHeal = true
            }

            let uncompletedItems = loaded.values
                .filter { $0.status == .queued }
                .sorted { a, b in
                    // Preserve episode order for the same series
                    if let sA = a.item.parentIndexNumber, let sB = b.item.parentIndexNumber,
                       let eA = a.item.indexNumber, let eB = b.item.indexNumber,
                       (a.item.seriesID == b.item.seriesID || a.item.seriesName == b.item.seriesName) {
                        if sA != sB { return sA < sB }
                        return eA < eB
                    }
                    return a.dateAdded < b.dateAdded
                }
            let queue = uncompletedItems.map(\.id)
            AppLogger.info("Loaded \(loaded.count) downloads from index (\(queue.count) queued)")
            return (loaded, queue, didHeal)
        } catch {
            AppLogger.error("Failed to load downloads index: \(error.localizedDescription)", error)
            return ([:], [], false)
        }
    }

    public func deleteFile(fileName: String) {
        let fileURL = downloadsDirectory.appendingPathComponent(fileName)
        try? fileManager.removeItem(at: fileURL)
    }

    public func deleteFiles(fileNames: [String]) {
        for fileName in fileNames {
            deleteFile(fileName: fileName)
        }
    }

    /// Deletes all files in the downloads directory that match the given item ID prefix
    public func deleteAllFiles(for itemID: String) {
        let dir = downloadsDirectory
        guard let files = try? fileManager.contentsOfDirectory(atPath: dir.path) else { return }
        for file in files where file.hasPrefix(itemID) {
            let fileURL = dir.appendingPathComponent(file)
            try? fileManager.removeItem(at: fileURL)
            AppLogger.info("Deleted download file: \(file)")
        }
    }

    /// Removes orphaned files from the downloads directory that are not tracked in the index
    public func cleanupOrphanedFiles(validFileNames: Set<String>) {
        let dir = downloadsDirectory
        guard let files = try? fileManager.contentsOfDirectory(atPath: dir.path) else { return }
        for file in files {
            if file == indexFileName || file.hasPrefix(".") { continue }
            if !validFileNames.contains(file) {
                let fileURL = dir.appendingPathComponent(file)
                try? fileManager.removeItem(at: fileURL)
                AppLogger.info("Cleaned up orphaned file: \(file)")
            }
        }
    }
}
