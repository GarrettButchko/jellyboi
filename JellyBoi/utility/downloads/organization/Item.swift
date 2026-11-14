//
//  Item.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 10/8/26.
//

import Foundation
import JellyfinAPI

extension DownloadStatus {
    public init(items: [DownloadItem]) {
        self.init(items.map(\.status))
    }
}

public nonisolated enum DownloadGroupType: String, Codable, Sendable {
    case show
    case collection
}

public nonisolated struct DownloadGroupInfo: Codable, Sendable, Equatable, Hashable {
    public let id: String
    public let title: String
    public let type: DownloadGroupType
    public let primaryImageTag: String?

    public init(
        id: String,
        title: String,
        type: DownloadGroupType,
        primaryImageTag: String? = nil
    ) {
        self.id = id
        self.title = title
        self.type = type
        self.primaryImageTag = primaryImageTag
    }

    @MainActor
    public func posterURL(client: JellyfinClient?) -> URL? {
        guard let client else { return nil }
        return client.itemImageURL(
            itemID: id,
            parameters: .poster(tag: primaryImageTag)
        )
    }
}

public nonisolated struct DownloadItem: Codable, Identifiable, Sendable, Equatable {
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
    public var group: DownloadGroupInfo?

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
        statusDetail: String? = nil,
        group: DownloadGroupInfo? = nil
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
        self.group = group
    }

    public static func == (lhs: DownloadItem, rhs: DownloadItem) -> Bool {
        lhs.id == rhs.id &&
        lhs.status == rhs.status &&
        lhs.progress == rhs.progress &&
        lhs.bytesDownloaded == rhs.bytesDownloaded &&
        lhs.totalBytes == rhs.totalBytes &&
        lhs.errorMessage == rhs.errorMessage &&
        lhs.estimatedTimeRemaining == rhs.estimatedTimeRemaining &&
        lhs.statusDetail == rhs.statusDetail &&
        lhs.group == rhs.group
    }

    public var title: String {
        if item.type == .episode {
            var label = ""
            if let s = item.parentIndexNumber, let e = item.indexNumber {
                label = "S\(s) E\(e)"
            }
            if let name = item.name, !name.isEmpty {
                label = label.isEmpty ? name : "\(label) • \(name)"
            }
            return label.isEmpty ? (item.name ?? "Episode") : label
        }
        return item.name ?? "Movie"
    }

    public static func formattedRemainingTime(from seconds: TimeInterval?) -> String? {
        guard let seconds, seconds.isFinite, seconds > 0 else {
            return nil
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

    public var formattedTimeRemaining: String {
        Self.formattedRemainingTime(from: estimatedTimeRemaining) ?? "Estimating..."
    }

    public func statusIcon(isCompleted: Bool = false) -> String {
        if isCompleted {
            return "checkmark.circle.fill"
        }
        return status.icon
    }

    public var statusIcon: String {
        statusIcon(isCompleted: false)
    }

    public var formattedFileSize: String {
        let bytes = totalBytes > 0 ? totalBytes : bytesDownloaded
        if bytes > 0 {
            return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        } else {
            return ""
        }
    }

    public var formattedPercentage: String {
        let percent = Int(progress * 100)
        return "\(percent)%"
    }

    // Don't change format
    public func statusText(isCompleted: Bool = false) -> String {
        if isCompleted || status == .completed {
            if !formattedFileSize.isEmpty {
                return "\(formattedFileSize)"
            }
            return "Downloaded"
        }

        switch status {
        case .downloading:
            if let time = Self.formattedRemainingTime(from: estimatedTimeRemaining) {
                return time
            }
            return "Downloading"
        case .converting, .finalizing:
            if let time = Self.formattedRemainingTime(from: estimatedTimeRemaining) {
                return time
            }
            return "Converting"
        case .queued:
            return "Queued"
        case .completed:
            if !formattedFileSize.isEmpty {
                return "\(formattedFileSize) • Downloaded"
            }
            return "Downloaded"
        case .failed:
            return "Failed"
        }
    }

    public var statusText: String {
        statusText(isCompleted: false)
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
