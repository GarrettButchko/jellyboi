//
//  DownloadPostProcessor.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 10/15/26.
//

import Foundation
import AVFoundation
import LoggingKit

public enum DownloadPostProcessor {
    public static func processDownloadedFile(
        itemID: String,
        itemTitle: String,
        tempLocation: URL,
        destinationURL: URL,
        rawContainer: String,
        targetAspect: String?,
        itemBytesDownloaded: Int64,
        onStateChange: @MainActor @Sendable @escaping (DownloadStatus, String?) -> Void,
        onProgress: @MainActor @Sendable @escaping (Double) -> Void
    ) async throws -> Int64 {
        let fileManager = FileManager.default

        if fileManager.fileExists(atPath: destinationURL.path) {
            try? fileManager.removeItem(at: destinationURL)
        }

        do {
            let isRawNative = ApplePlayableContainer.contains(rawContainer)
            var shouldUseDirect = false

            if isRawNative {
                let asset = AVURLAsset(url: tempLocation)
                if let isPlayable = try? await asset.load(.isPlayable), isPlayable {
                    var hasAspectMismatch = false
                    if let targetAspect = targetAspect,
                       let targetDAR = PlayerViewModel.parseAspectRatio(targetAspect),
                       let tracks = try? await asset.loadTracks(withMediaType: .video),
                       let track = tracks.first,
                       let natSize = try? await track.load(.naturalSize),
                       natSize.width > 0, natSize.height > 0 {
                        let trackDAR = natSize.width / natSize.height
                        if abs(trackDAR - targetDAR) / targetDAR > 0.02 {
                            hasAspectMismatch = true
                            AppLogger.info("Raw native container has aspect ratio mismatch (track: \(String(format: "%.2f", trackDAR)), target: \(String(format: "%.2f", targetDAR))); remuxing to normalize")
                        }
                    }
                    if !hasAspectMismatch {
                        shouldUseDirect = true
                    }
                }
            }

            if shouldUseDirect {
                onStateChange(.finalizing, "Finalizing...")
                try fileManager.moveItem(at: tempLocation, to: destinationURL)
            } else {
                onStateChange(.converting, "Converting video...")
                AppLogger.info("Processing downloaded container (\(rawContainer.isEmpty ? "unknown" : rawContainer)) to compliant MP4 for '\(itemTitle)'")

                var lastDispatchedTime: TimeInterval = 0
                var lastDispatchedPercent: Int = -1

                try await LocalMediaRemuxer.remuxToMP4Async(
                    inputURL: tempLocation,
                    outputURL: destinationURL,
                    targetAspectRatio: targetAspect
                ) { progress in
                    let now = Date().timeIntervalSince1970
                    let pct = Int(progress * 100)
                    if now - lastDispatchedTime >= 0.25 || pct != lastDispatchedPercent {
                        lastDispatchedTime = now
                        lastDispatchedPercent = pct
                        Task { @MainActor in
                            onProgress(progress)
                        }
                    }
                }
                try? fileManager.removeItem(at: tempLocation)
            }

            let attributes = try fileManager.attributesOfItem(atPath: destinationURL.path)
            return attributes[.size] as? Int64 ?? itemBytesDownloaded
        } catch {
            // Clean up any incomplete destination file immediately on failure
            try? fileManager.removeItem(at: destinationURL)
            throw error
        }
    }
}
