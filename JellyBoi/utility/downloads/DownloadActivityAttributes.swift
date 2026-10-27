//
//  DownloadActivityAttributes.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 10/20/26.
//

import Foundation
import ActivityKit

public nonisolated struct DownloadActivityAttributes: Sendable {
    public struct ContentState: Codable, Hashable, Sendable {
        public var title: String
        public var subtitle: String?
        public var detailText: String?
        public var progress: Double
        public var itemsRemaining: Int
        public var totalItems: Int
        public var isCompleted: Bool
        public var posterImageData: Data?
        public var statusIcon: String
        public var statusText: String
        public var isQueued: Bool
        public var isConverting: Bool
        public var isSingleElement: Bool

        public init(
            title: String,
            subtitle: String? = nil,
            detailText: String? = nil,
            progress: Double,
            itemsRemaining: Int,
            totalItems: Int,
            isCompleted: Bool = false,
            posterImageData: Data? = nil,
            statusIcon: String = "arrow.down",
            statusText: String = "Downloading",
            isQueued: Bool = false,
            isConverting: Bool = false,
            isSingleElement: Bool = true
        ) {
            self.title = title
            self.subtitle = subtitle
            self.detailText = detailText
            self.progress = progress
            self.itemsRemaining = itemsRemaining
            self.totalItems = totalItems
            self.isCompleted = isCompleted
            self.posterImageData = posterImageData
            self.statusIcon = statusIcon
            self.statusText = statusText
            self.isQueued = isQueued
            self.isConverting = isConverting
            self.isSingleElement = isSingleElement
        }
    }

    public var groupID: String?

    public init(groupID: String? = nil) {
        self.groupID = groupID
    }
}

nonisolated extension DownloadActivityAttributes: ActivityAttributes {}
