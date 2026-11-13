//
//  Manager+URLSession.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 10/8/26.
//

import Foundation
import LoggingKit

// MARK: - URLSessionDownloadDelegate

extension DownloadManager {
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
        // Move to download directory staging location immediately before system deletes temp file
        let downloadsDir = DownloadStorage.downloadsDirectoryURL
        let stagedURL = downloadsDir.appendingPathComponent(".staging-\(UUID().uuidString)")
        do {
            if FileManager.default.fileExists(atPath: stagedURL.path) {
                try FileManager.default.removeItem(at: stagedURL)
            }
            try FileManager.default.moveItem(at: location, to: stagedURL)
        } catch {
            AppLogger.error("Failed to move downloaded file to staging location: \(error.localizedDescription)", error)
            // Fallback to copy if cross-volume move fails
            try? FileManager.default.copyItem(at: location, to: stagedURL)
        }

        Task { @MainActor in
            DownloadManager.shared.handleCompleted(itemID: itemID, stagedLocation: stagedURL)
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

    public nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor in
            AppLogger.info("urlSessionDidFinishEventsForBackgroundURLSession called")
            DownloadManager.shared.callBackgroundCompletionHandlerIfNeeded()
        }
    }
}
