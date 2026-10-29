//
//  DownloadActivityAttributes.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 10/20/26.
//

import Foundation
import ActivityKit
import SwiftUI

public nonisolated enum DownloadStatus: String, Codable, Hashable, Sendable {
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

    public var icon: String {
        switch self {
        case .queued:
            return "clock"
        case .downloading:
            return "arrow.down"
        case .converting, .finalizing:
            return "arrow.triangle.2.circlepath"
        case .completed:
            return "checkmark"
        case .failed:
            return "exclamationmark.triangle"
        }
    }

    public var iconName: String { icon }

    public var text: String {
        switch self {
        case .queued:
            return "Queued"
        case .downloading:
            return "Downloading"
        case .converting:
            return "Converting"
        case .finalizing:
            return "Finalizing"
        case .completed:
            return "Ready offline"
        case .failed:
            return "Failed"
        }
    }

    public var tintColor: Color {
        switch self {
        case .completed:
            return .green
        case .queued:
            return .orange
        case .converting, .finalizing:
            return .purple
        case .downloading, .failed:
            return .indigo
        }
    }

    public var isQueued: Bool { self == .queued }
    public var isConverting: Bool { self == .converting || self == .finalizing }
    public var isCompleted: Bool { self == .completed }
    public var isFailed: Bool { self == .failed }
    public var isDownloading: Bool { self == .downloading }
    public var isActive: Bool { self == .downloading || self == .converting || self == .finalizing }

    public init(status: DownloadStatus) {
        self = status
    }

    public init<S: Sequence>(_ statuses: S) where S.Element == DownloadStatus {
        let list = Array(statuses)
        if list.isEmpty {
            self = .completed
        } else if list.allSatisfy({ $0 == .failed }) {
            self = .failed
        } else if list.contains(where: { $0 == .converting || $0 == .finalizing }) {
            self = .converting
        } else if list.contains(where: { $0 == .downloading }) {
            self = .downloading
        } else if list.allSatisfy({ $0 == .queued }) {
            self = .queued
        } else {
            self = .downloading
        }
    }

    public init(_ statuses: DownloadStatus...) {
        self.init(statuses)
    }
}

public nonisolated struct DownloadActivityAttributes: Sendable {
    public struct ContentState: Codable, Hashable, Sendable {
        public var title: String
        public var subtitle: String?
        public var detailText: String?
        public var progress: Double
        public var itemsRemaining: Int
        public var totalItems: Int
        public var status: DownloadStatus
        public var posterImageData: Data?
        public var isSingleElement: Bool

        public var statusIcon: String { status.icon }
        public var statusText: String { status.text }
        public var tintColor: Color { status.tintColor }
        public var isQueued: Bool { status.isQueued }
        public var isConverting: Bool { status.isConverting }
        public var isCompleted: Bool { status.isCompleted }

        public var progressPercent: Int {
            Int(progress * 100)
        }

        public var percentageText: String {
            switch status {
            case .completed:
                return "Done"
            case .queued:
                return "Queued"
            default:
                return "\(progressPercent)%"
            }
        }

        public var compactPercentageText: String {
            switch status {
            case .completed:
                return "100%"
            case .queued:
                return "Queued"
            default:
                return "\(progressPercent)%"
            }
        }

        public var compactPercentageColor: Color {
            switch status {
            case .completed:
                return .green
            case .queued:
                return .orange
            default:
                return Color.white.opacity(0.9)
            }
        }

        public var statusDetail: String {
            switch status {
            case .completed:
                return "Ready offline"
            case .queued:
                if itemsRemaining > 1 {
                    return "\(itemsRemaining) items queued"
                }
                return "Queued"
            case .converting, .finalizing:
                if itemsRemaining > 1 {
                    return "\(itemsRemaining) left • Converting"
                }
                return "Converting"
            case .failed:
                return "Failed"
            case .downloading:
                if let extra = Self.cleanExtraInfo(detailText, itemsRemaining: itemsRemaining) {
                    return extra
                }
                if let subtitle, !subtitle.isEmpty {
                    return subtitle
                }
                if itemsRemaining > 1 {
                    return "\(itemsRemaining) items left"
                }
                return "Downloading"
            }
        }

        public static func cleanExtraInfo(_ detailText: String?, itemsRemaining: Int) -> String? {
            guard let detailText, !detailText.isEmpty else { return nil }
            let components = detailText.components(separatedBy: "•").map { $0.trimmingCharacters(in: .whitespaces) }
            let nonPercent = components.filter { !$0.contains("%") }

            for item in nonPercent {
                if itemsRemaining > 1 && (item.contains("item") || item.contains("episode")) {
                    continue
                }
                return item
            }
            return nonPercent.first
        }

        public init(
            title: String,
            subtitle: String? = nil,
            detailText: String? = nil,
            progress: Double,
            itemsRemaining: Int,
            totalItems: Int,
            status: DownloadStatus = .downloading,
            posterImageData: Data? = nil,
            isSingleElement: Bool = true
        ) {
            self.title = title
            self.subtitle = subtitle
            self.detailText = detailText
            self.progress = progress
            self.itemsRemaining = itemsRemaining
            self.totalItems = totalItems
            self.status = status
            self.posterImageData = posterImageData
            self.isSingleElement = isSingleElement
        }
    }

    public var groupID: String?

    public init(groupID: String? = nil) {
        self.groupID = groupID
    }
}

nonisolated extension DownloadActivityAttributes: ActivityAttributes {}
