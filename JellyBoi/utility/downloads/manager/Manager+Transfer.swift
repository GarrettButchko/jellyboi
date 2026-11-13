//
//  Manager+Transfer.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 10/8/26.
//

import Foundation
import JellyfinAPI
import LoggingKit
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Internal Session & Progress Handling

extension DownloadManager {
    func handleProgress(
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

    func handleCompleted(itemID: String, stagedLocation: URL) {
        guard var item = downloads[itemID] else {
            try? FileManager.default.removeItem(at: stagedLocation)
            return
        }
        let destinationURL = storage.downloadsDirectory.appendingPathComponent(item.fileName)

        let rawContainer = item.item.container?.lowercased() ?? ""
        let isRawNative = ApplePlayableContainer.supports(rawContainer)
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

        #if os(iOS)
        var backgroundTaskID = UIBackgroundTaskIdentifier.invalid
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "com.jellyboi.finalize-\(itemID)") {
            AppLogger.warning("Background task expired while post-processing '\(itemTitle)'")
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
            backgroundTaskID = .invalid
        }
        #endif

        Task.detached(priority: .utility) {
            defer {
                #if os(iOS)
                if backgroundTaskID != .invalid {
                    UIApplication.shared.endBackgroundTask(backgroundTaskID)
                    backgroundTaskID = .invalid
                }
                #endif
            }

            do {
                let fileSize = try await DownloadPostProcessor.processDownloadedFile(
                    itemID: itemID,
                    itemTitle: itemTitle,
                    tempLocation: stagedLocation,
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
                try? FileManager.default.removeItem(at: stagedLocation)
                try? FileManager.default.removeItem(at: destinationURL)
                await MainActor.run {
                    DownloadManager.shared.finishItemFailed(itemID: itemID, error: error)
                }
            }
        }
    }

    func handleError(itemID: String, error: Error, resumeData: Data?) {
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

            AppLogger.warning("Transient network error for '\(item.title)' (\(error.localizedDescription)). Retrying with resumeData in \(attempts + 1)s (attempt \(attempts + 1)/5)...")

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

        AppLogger.error("Download failed for '\(item.title)': \(item.errorMessage ?? "")")
        processQueue()
    }
}

// MARK: - Post-Processing State Updates

extension DownloadManager {
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

        AppLogger.success("Download and processing completed successfully for '\(item.title)'")
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

        AppLogger.error("Failed to finalize downloaded file for '\(item.title)': \(error.localizedDescription)", error)
        processQueue()
    }
}
