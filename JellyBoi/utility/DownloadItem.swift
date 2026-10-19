//
//  DownloadItem.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 10/8/26.
//

import Foundation
import JellyfinAPI

public enum DownloadStatus: String, Codable, Sendable {
    case queued
    case downloading
    case converting
    case finalizing
    case completed
    case failed

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        switch raw {
        case "downloading": self = .downloading
        case "converting": self = .converting
        case "finalizing": self = .finalizing
        case "completed": self = .completed
        case "failed": self = .failed
        default: self = .queued
        }
    }
}

public struct DownloadItem: Codable, Identifiable, Sendable, Equatable {
    public let id: String
    public var item: BaseItemDto
    public let fileName: String
    public var status: DownloadStatus
    public var progress: Double
    public var bytesDownloaded: Int64
    public var totalBytes: Int64
    public let dateAdded: Date
    public var dateCompleted: Date?
    public var errorMessage: String?
    public var estimatedTimeRemaining: TimeInterval?
    public var statusDetail: String?

    public init(
        id: String,
        item: BaseItemDto,
        fileName: String,
        status: DownloadStatus,
        progress: Double,
        bytesDownloaded: Int64,
        totalBytes: Int64,
        dateAdded: Date,
        dateCompleted: Date? = nil,
        errorMessage: String? = nil,
        estimatedTimeRemaining: TimeInterval? = nil,
        statusDetail: String? = nil
    ) {
        self.id = id
        self.item = item
        self.fileName = fileName
        self.status = status
        self.progress = progress
        self.bytesDownloaded = bytesDownloaded
        self.totalBytes = totalBytes
        self.dateAdded = dateAdded
        self.dateCompleted = dateCompleted
        self.errorMessage = errorMessage
        self.estimatedTimeRemaining = estimatedTimeRemaining
        self.statusDetail = statusDetail
    }

    public static func == (lhs: DownloadItem, rhs: DownloadItem) -> Bool {
        lhs.id == rhs.id &&
        lhs.status == rhs.status &&
        lhs.progress == rhs.progress &&
        lhs.bytesDownloaded == rhs.bytesDownloaded &&
        lhs.totalBytes == rhs.totalBytes &&
        lhs.errorMessage == rhs.errorMessage &&
        lhs.estimatedTimeRemaining == rhs.estimatedTimeRemaining &&
        lhs.statusDetail == rhs.statusDetail
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

    public var formattedTimeRemaining: String {
        guard let seconds = estimatedTimeRemaining, seconds.isFinite, seconds > 0 else {
            return "Estimating..."
        }

        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60

        if hours > 0 {
            let hrUnit = hours == 1 ? "hr" : "hrs"
            if minutes > 0 {
                return "\(hours) \(hrUnit) \(minutes) min\(minutes == 1 ? "" : "s") left"
            } else {
                return "\(hours) \(hrUnit) left"
            }
        } else if minutes > 0 {
            return "\(minutes) min\(minutes == 1 ? "" : "s") left"
        } else {
            return "\(max(secs, 1)) sec left"
        }
    }

    public var statusIcon: String? {
        switch status {
        case .downloading:
            return "arrow.down"
        case .converting:
            return "arrow.triangle.2.circlepath"
        case .finalizing:
            return "arrow.triangle.2.circlepath"
        default:
            return nil
        }
    }

    public var formattedFileSize: String {
        let bytes = totalBytes > 0 ? totalBytes : bytesDownloaded
        if bytes > 0 {
            return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        } else {
            return ""
        }
    }

    public var formattedProgress: String {
        formattedTimeRemaining
    }

    public var formattedPercentage: String {
        let percent = Int(progress * 100)
        return "\(percent)%"
    }

    public var statusText: String {
        switch status {
        case .queued:
            return "Queued"
        case .downloading:
            return formattedTimeRemaining
        case .converting:
            if let seconds = estimatedTimeRemaining, seconds.isFinite, seconds > 0 {
                return formattedTimeRemaining
            }
            return "Converting..."
        case .finalizing:
            if let seconds = estimatedTimeRemaining, seconds.isFinite, seconds > 0 {
                return formattedTimeRemaining
            }
            return "Finalizing..."
        case .completed:
            return "Downloaded"
        case .failed:
            return errorMessage ?? "Download failed"
        }
    }

    public var formatBadge: String {
        let ext = (fileName as NSString).pathExtension.uppercased()
        let raw = item.container?.uppercased() ?? ext
        if !raw.isEmpty && raw != ext {
            return "\(raw) ➔ \(ext)"
        }
        return ext.isEmpty ? "MP4" : ext
    }
}
