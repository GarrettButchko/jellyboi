//
//  DownloadProgressTracker.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 10/15/26.
//

import Foundation

public final class DownloadProgressTracker: @unchecked Sendable {
    private struct SpeedSample {
        let timestamp: TimeInterval
        let bytes: Int64
    }

    private var speedSamples: [String: [SpeedSample]] = [:]
    private var smoothedSpeed: [String: Double] = [:]
    private var conversionStartTime: [String: TimeInterval] = [:]
    private var smoothedConversionRate: [String: Double] = [:]
    private var lastProgressUpdateTime: [String: TimeInterval] = [:]

    public init() {}

    /// Checks if progress update should be throttled to avoid excessive UI redraws.
    public func shouldThrottleDownload(
        itemID: String,
        now: TimeInterval = Date().timeIntervalSince1970,
        totalBytesWritten: Int64,
        totalBytesExpected: Int64
    ) -> Bool {
        let lastUpdate = lastProgressUpdateTime[itemID] ?? 0
        guard now - lastUpdate > 0.2 || totalBytesWritten >= totalBytesExpected else {
            return true
        }
        lastProgressUpdateTime[itemID] = now
        return false
    }

    /// Computes smoothed progress and estimated time remaining for an active download.
    public func calculateDownloadProgress(
        itemID: String,
        now: TimeInterval = Date().timeIntervalSince1970,
        totalBytesWritten: Int64,
        totalBytesExpected: Int64
    ) -> (progress: Double, eta: TimeInterval?) {
        let progress = totalBytesExpected > 0 ? Double(totalBytesWritten) / Double(totalBytesExpected) : 0.0

        var samples = speedSamples[itemID] ?? []
        samples.append(SpeedSample(timestamp: now, bytes: totalBytesWritten))
        samples = samples.filter { now - $0.timestamp <= 3.0 }
        speedSamples[itemID] = samples

        var eta: TimeInterval? = nil
        if let first = samples.first, let last = samples.last, last.timestamp - first.timestamp >= 0.4 {
            let dt = last.timestamp - first.timestamp
            let db = Double(last.bytes - first.bytes)
            if dt > 0 && db > 0 {
                let instantSpeed = db / dt
                let previousSpeed = smoothedSpeed[itemID] ?? instantSpeed
                let currentSpeed = 0.7 * instantSpeed + 0.3 * previousSpeed
                smoothedSpeed[itemID] = currentSpeed

                if totalBytesExpected > totalBytesWritten && currentSpeed > 1024 {
                    let remainingBytes = Double(totalBytesExpected - totalBytesWritten)
                    eta = remainingBytes / currentSpeed
                }
            }
        }

        return (progress, eta)
    }

    /// Marks the start time for the post-processing / conversion step.
    public func startConversion(
        itemID: String,
        now: TimeInterval = Date().timeIntervalSince1970
    ) {
        conversionStartTime[itemID] = now
        smoothedConversionRate.removeValue(forKey: itemID)
    }

    /// Computes rate and ETA for video conversion, and determines whether UI should update.
    public func calculateConversionProgress(
        itemID: String,
        now: TimeInterval = Date().timeIntervalSince1970,
        progress: Double,
        previousProgress: Double,
        previousETA: TimeInterval?
    ) -> (progress: Double, eta: TimeInterval?, shouldUpdate: Bool) {
        let cappedProgress = min(max(progress, 0.0), 1.0)
        let pct = Int(cappedProgress * 100)
        let currentPct = Int(previousProgress * 100)

        var eta = previousETA

        if let startTime = conversionStartTime[itemID], cappedProgress > 0.02 && cappedProgress < 1.0 {
            let elapsed = now - startTime
            if elapsed >= 0.5 {
                let instantRate = cappedProgress / elapsed
                let previousRate = smoothedConversionRate[itemID] ?? instantRate
                let currentRate = 0.7 * instantRate + 0.3 * previousRate
                smoothedConversionRate[itemID] = currentRate

                if currentRate > 0.0005 {
                    let remaining = (1.0 - cappedProgress) / currentRate
                    if remaining > 0 && remaining.isFinite {
                        eta = remaining
                    }
                }
            }
        }

        let timeChanged: Bool = {
            guard let cur = eta else { return false }
            let prev = previousETA ?? 0
            return abs(cur - prev) >= 1.0
        }()

        let shouldUpdate = pct != currentPct || abs(cappedProgress - previousProgress) >= 0.01 || timeChanged
        return (cappedProgress, eta, shouldUpdate)
    }

    /// Clears tracking data for a specific item.
    public func clear(itemID: String) {
        speedSamples.removeValue(forKey: itemID)
        smoothedSpeed.removeValue(forKey: itemID)
        conversionStartTime.removeValue(forKey: itemID)
        smoothedConversionRate.removeValue(forKey: itemID)
        lastProgressUpdateTime.removeValue(forKey: itemID)
    }

    /// Clears tracking data for all items.
    public func clearAll() {
        speedSamples.removeAll()
        smoothedSpeed.removeAll()
        conversionStartTime.removeAll()
        smoothedConversionRate.removeAll()
        lastProgressUpdateTime.removeAll()
    }
}
