//
//  ActivityAttributes.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 10/24/26.
//

import ActivityKit
import Foundation
import SwiftUI

// MARK: - Unified Download Status

public enum DownloadStatus: String, Codable, Sendable {
    case queued
    case downloading
    case converting
    case finalizing
    case completed
    case failed

    public var isQueued: Bool {
        self == .queued
    }

    public var isCompleted: Bool {
        self == .completed
    }

    public var isFailed: Bool {
        self == .failed
    }

    public var isConverting: Bool {
        self == .converting || self == .finalizing
    }

    public var isDownloading: Bool {
        self == .downloading
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

    public var accentColor: Color {
        switch self {
        case .completed:
            return .green
        case .queued:
            return .orange
        case .converting, .finalizing:
            return .purple
        case .failed:
            return .red
        case .downloading:
            return .accentColor
        }
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

// MARK: - Download Presentation State Kind

public enum DownloadPresentationStateKind: Int, Codable, Sendable {
    case group = 1      // Collection or Series
    case episode = 2    // Single episode
    case movie = 3      // Single movie
    case multiple = 4   // Multiple items across different groups/types
}

public nonisolated struct DownloadActivityAttributes: Sendable {
    public struct ContentState: Codable, Hashable, Sendable {
        public var stateKind: DownloadPresentationStateKind
        public var title: String
        public var subtitleLeftText: String?
        public var subtitleLeftIcon: String?
        public var subtitleRightText: String?
        public var subtitle: String?
        public var detailText: String?
        public var progress: Double
        public var itemsRemaining: Int
        public var totalItems: Int
        public var status: DownloadStatus
        public var posterImageData: Data?
        public var isSingleElement: Bool
        public var isEpisode: Bool

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
            case .completed, .queued:
                return Color.accentColor
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
                if let extra = Self.cleanExtraInfo(detailText, itemsRemaining: itemsRemaining) {
                    return extra
                }
                if let subtitle, !subtitle.isEmpty {
                    return subtitle
                }
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

            if let timeItem = nonPercent.first(where: { $0.contains("min") || $0.contains("sec") || $0.contains("hr") }) {
                return timeItem
            }

            for item in nonPercent {
                if itemsRemaining > 1 && (item.contains("item") || item.contains("episode")) {
                    continue
                }
                return item
            }
            return nonPercent.first
        }

        public init(
            stateKind: DownloadPresentationStateKind = .multiple,
            title: String,
            subtitleLeftText: String? = nil,
            subtitleLeftIcon: String? = nil,
            subtitleRightText: String? = nil,
            subtitle: String? = nil,
            detailText: String? = nil,
            progress: Double,
            itemsRemaining: Int,
            totalItems: Int,
            status: DownloadStatus = .downloading,
            posterImageData: Data? = nil,
            isSingleElement: Bool = true,
            isEpisode: Bool = false
        ) {
            self.stateKind = stateKind
            self.title = title
            self.subtitleLeftText = subtitleLeftText
            self.subtitleLeftIcon = subtitleLeftIcon
            self.subtitleRightText = subtitleRightText
            self.subtitle = subtitle
            self.detailText = detailText
            self.progress = progress
            self.itemsRemaining = itemsRemaining
            self.totalItems = totalItems
            self.status = status
            self.posterImageData = posterImageData
            self.isSingleElement = isSingleElement
            self.isEpisode = isEpisode
        }

        enum CodingKeys: String, CodingKey {
            case stateKind, title, subtitleLeftText, subtitleLeftIcon, subtitleRightText
            case subtitle, detailText, progress, itemsRemaining, totalItems, status
            case posterImageData, isSingleElement, isEpisode
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.stateKind = try container.decodeIfPresent(DownloadPresentationStateKind.self, forKey: .stateKind) ?? .multiple
            self.title = try container.decode(String.self, forKey: .title)
            self.subtitleLeftText = try container.decodeIfPresent(String.self, forKey: .subtitleLeftText)
            self.subtitleLeftIcon = try container.decodeIfPresent(String.self, forKey: .subtitleLeftIcon)
            self.subtitleRightText = try container.decodeIfPresent(String.self, forKey: .subtitleRightText)
            self.subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle)
            self.detailText = try container.decodeIfPresent(String.self, forKey: .detailText)
            self.progress = try container.decode(Double.self, forKey: .progress)
            self.itemsRemaining = try container.decode(Int.self, forKey: .itemsRemaining)
            self.totalItems = try container.decode(Int.self, forKey: .totalItems)
            self.status = try container.decode(DownloadStatus.self, forKey: .status)
            self.posterImageData = try container.decodeIfPresent(Data.self, forKey: .posterImageData)
            self.isSingleElement = try container.decodeIfPresent(Bool.self, forKey: .isSingleElement) ?? true
            self.isEpisode = try container.decodeIfPresent(Bool.self, forKey: .isEpisode) ?? false
        }
    }

    public var groupID: String?

    public init(groupID: String? = nil) {
        self.groupID = groupID
    }
}

nonisolated extension DownloadActivityAttributes: ActivityAttributes {}
