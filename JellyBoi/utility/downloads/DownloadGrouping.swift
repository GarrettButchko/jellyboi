//
//  DownloadGrouping.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 10/20/26.
//

import Foundation
import SwiftUI
import JellyfinAPI

public struct ShowDownloadGroup: Identifiable, Equatable, Sendable, Hashable {
    public let id: String
    public let seriesName: String
    public let groupInfo: DownloadGroupInfo?
    public let activeDownloads: [DownloadItem]
    public let completedDownloads: [DownloadItem]

    public init(
        id: String,
        seriesName: String,
        groupInfo: DownloadGroupInfo? = nil,
        activeDownloads: [DownloadItem],
        completedDownloads: [DownloadItem]
    ) {
        self.id = id
        self.seriesName = seriesName
        self.groupInfo = groupInfo
        self.activeDownloads = activeDownloads
        self.completedDownloads = completedDownloads
    }

    public var totalCount: Int { activeDownloads.count + completedDownloads.count }
    public var episodesLeft: Int { activeDownloads.count }

    public var overallProgress: Double {
        guard totalCount > 0 else { return 0 }
        let completed = Double(completedDownloads.count)
        let active = activeDownloads.reduce(0.0) { $0 + $1.progress }
        return (completed + active) / Double(totalCount)
    }

    public var status: DownloadStatus {
        DownloadStatus(items: activeDownloads)
    }

    public var isAllFailed: Bool {
        status == .failed
    }

    public var isAllQueued: Bool {
        status == .queued
    }

    public var isConverting: Bool {
        status == .converting
    }

    public var representativeItem: BaseItemDto? {
        activeDownloads.first?.item ?? completedDownloads.first?.item
    }

    func posterURL(client: JellyfinClient?, libraryViewModel: LibraryViewModel? = nil) -> URL? {
        if let directURL = groupInfo?.posterURL(client: client) {
            return directURL
        }
        guard let client else { return nil }
        if let libraryViewModel {
            if groupInfo?.type == .collection {
                if let collection = libraryViewModel.collections.first(where: { $0.id == id }) {
                    return libraryViewModel.posterURL(for: collection, client: client)
                }
            } else {
                if let show = libraryViewModel.tvShows.first(where: { $0.id == id }) {
                    return libraryViewModel.posterURL(for: show, client: client)
                }
                if let first = representativeItem, let url = libraryViewModel.seriesPosterURL(for: first, client: client) {
                    return url
                }
            }
        }
        return client.itemImageURL(
            itemID: id,
            parameters: .poster()
        )
    }

    public static func formattedTimeRemaining(for items: [DownloadItem]) -> String? {
        let isAllFailed = !items.isEmpty && items.allSatisfy { $0.status == .failed }
        guard !isAllFailed else { return nil }

        // Do not show time remaining for the group as a whole when multiple items are queued/active.
        // Time remaining only shows when the single remaining item is the one downloading.
        guard items.count == 1,
              let activeItem = items.first,
              activeItem.status == .downloading,
              let time = activeItem.estimatedTimeRemaining, time > 0 else {
            return nil
        }
        return activeItem.formattedTimeRemaining
    }

    public var formattedTimeRemaining: String? {
        Self.formattedTimeRemaining(for: activeDownloads)
    }

    public var activeStatusIcon: String? {
        guard !activeDownloads.isEmpty else { return nil }
        return status.icon
    }

    public static func == (lhs: ShowDownloadGroup, rhs: ShowDownloadGroup) -> Bool {
        lhs.id == rhs.id &&
        lhs.seriesName == rhs.seriesName &&
        lhs.groupInfo == rhs.groupInfo &&
        lhs.activeDownloads == rhs.activeDownloads &&
        lhs.completedDownloads == rhs.completedDownloads
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

public struct DownloadSummaryPresentation: Equatable, Sendable {
    public let title: String
    public let subtitle: String?
    public let detailText: String?
    public let progress: Double
    public let itemsRemaining: Int
    public let totalItems: Int
    public let status: DownloadStatus
    public let posterImageData: Data?
    public let posterURL: URL?
    public let isSingleElement: Bool

    public var statusIcon: String { status.icon }
    public var statusText: String { status.text }
    public var tintColor: Color { status.tintColor }
    public var isQueued: Bool { status.isQueued }
    public var isConverting: Bool { status.isConverting }
    public var isCompleted: Bool { status.isCompleted }

    public init(
        title: String,
        subtitle: String? = nil,
        detailText: String? = nil,
        progress: Double,
        itemsRemaining: Int,
        totalItems: Int,
        status: DownloadStatus = .downloading,
        posterImageData: Data? = nil,
        posterURL: URL? = nil,
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
        self.posterURL = posterURL
        self.isSingleElement = isSingleElement
    }

    public func contentState(fallbackPosterData: Data? = nil) -> DownloadActivityAttributes.ContentState {
        DownloadActivityAttributes.ContentState(
            title: title,
            subtitle: subtitle,
            detailText: detailText,
            progress: progress,
            itemsRemaining: itemsRemaining,
            totalItems: totalItems,
            status: status,
            posterImageData: isSingleElement ? (posterImageData ?? fallbackPosterData) : nil,
            isSingleElement: isSingleElement
        )
    }

    public var statusDetail: String {
        contentState().statusDetail
    }

    public var percentageText: String {
        contentState().percentageText
    }

    public func with(posterImageData: Data?) -> DownloadSummaryPresentation {
        DownloadSummaryPresentation(
            title: title,
            subtitle: subtitle,
            detailText: detailText,
            progress: progress,
            itemsRemaining: itemsRemaining,
            totalItems: totalItems,
            status: status,
            posterImageData: posterImageData,
            posterURL: posterURL,
            isSingleElement: isSingleElement
        )
    }
}

public enum DownloadGrouping {
    public static func groups(from active: [DownloadItem], completed: [DownloadItem]) -> [ShowDownloadGroup] {
        var groupMap: [String: (name: String, groupInfo: DownloadGroupInfo?, active: [DownloadItem])] = [:]
        for item in active {
            guard let group = item.group else { continue }
            let groupID = group.id
            let groupName = group.title
            if groupMap[groupID] == nil {
                groupMap[groupID] = (name: groupName, groupInfo: group, active: [item])
            } else {
                groupMap[groupID]?.active.append(item)
            }
        }

        var result: [ShowDownloadGroup] = []
        for (id, data) in groupMap {
            let matchingCompleted = completed.filter { $0.group?.id == id }
            result.append(ShowDownloadGroup(
                id: id,
                seriesName: data.name,
                groupInfo: data.groupInfo,
                activeDownloads: data.active,
                completedDownloads: matchingCompleted
            ))
        }

        return result.sorted { $0.seriesName.localizedCaseInsensitiveCompare($1.seriesName) == .orderedAscending }
    }

    public static func standaloneDownloads(from active: [DownloadItem], groupedIDs: Set<String>) -> [DownloadItem] {
        active.filter { item in
            guard let group = item.group else { return true }
            return !groupedIDs.contains(group.id)
        }
    }

    public static func activeStatusIcon(for items: [DownloadItem]) -> String {
        DownloadStatus(items: items).icon
    }

    public static func currentPresentation(
        active: [DownloadItem],
        completed: [DownloadItem],
        client: JellyfinClient? = nil
    ) -> DownloadSummaryPresentation {
        guard !active.isEmpty else {
            return DownloadSummaryPresentation(
                title: "Downloads Complete",
                subtitle: "All items ready offline",
                detailText: "100%",
                progress: 1.0,
                itemsRemaining: 0,
                totalItems: completed.count,
                status: .completed,
                posterImageData: nil,
                posterURL: nil,
                isSingleElement: false
            )
        }

        let computedGroups = groups(from: active, completed: completed)
        let standalones = standaloneDownloads(from: active, groupedIDs: Set(computedGroups.map(\.id)))
        let totalActiveCount = active.count
        let totalItemsCount = active.count + completed.count

        // Case 1: Exactly 1 group (Series or Collection) and no standalone items -> 1 element (shows poster)
        if computedGroups.count == 1 && standalones.isEmpty, let singleGroup = computedGroups.first {
            let activeItem = singleGroup.activeDownloads.first(where: { $0.status == .downloading || $0.status == .converting || $0.status == .finalizing }) ?? singleGroup.activeDownloads.first
            var subtitleText: String?
            if let activeItem {
                let status = activeItem.statusDetail ?? (activeItem.status == .downloading ? "Downloading" : activeItem.status.rawValue.capitalized)
                subtitleText = "\(activeItem.title) • \(status)"
            }

            let itemWord = singleGroup.groupInfo?.type == .collection ? (singleGroup.episodesLeft == 1 ? "item" : "items") : (singleGroup.episodesLeft == 1 ? "episode" : "episodes")

            var detail: String?
            if singleGroup.isAllFailed {
                detail = "\(singleGroup.episodesLeft) \(itemWord) left (Failed)"
            } else if singleGroup.isAllQueued {
                detail = "\(singleGroup.episodesLeft) \(itemWord) queued"
            } else if let timeRemaining = singleGroup.formattedTimeRemaining {
                detail = "\(singleGroup.episodesLeft) left • \(timeRemaining)"
            } else {
                detail = "\(singleGroup.episodesLeft) \(itemWord) left"
            }

            let posterURL = singleGroup.posterURL(client: client)

            return DownloadSummaryPresentation(
                title: singleGroup.seriesName,
                subtitle: subtitleText,
                detailText: detail,
                progress: singleGroup.overallProgress,
                itemsRemaining: singleGroup.episodesLeft,
                totalItems: singleGroup.totalCount,
                status: singleGroup.status,
                posterImageData: nil,
                posterURL: posterURL,
                isSingleElement: true
            )
        }

        // Case 2: Exactly 1 standalone item (Movie or standalone Episode) and no groups -> 1 element (shows poster)
        if computedGroups.isEmpty && standalones.count == 1, let singleItem = standalones.first {
            let status = singleItem.statusDetail ?? (singleItem.status == .downloading ? "Downloading" : singleItem.status.rawValue.capitalized)
            var detail: String?
            if singleItem.status == .queued {
                detail = "Queued"
            } else if singleItem.status == .failed {
                detail = "Failed"
            } else if let time = singleItem.estimatedTimeRemaining, time > 0 {
                let cleanTime = singleItem.formattedTimeRemaining.replacingOccurrences(of: " left", with: "")
                detail = "\(cleanTime) • \(Int(singleItem.progress * 100))%"
            } else {
                detail = "\(status) • \(Int(singleItem.progress * 100))%"
            }

            var byteProgressText: String?
            if singleItem.totalBytes > 0 && singleItem.status != .queued {
                let downloadedStr = ByteCountFormatter.string(fromByteCount: singleItem.bytesDownloaded, countStyle: .file)
                let totalStr = ByteCountFormatter.string(fromByteCount: singleItem.totalBytes, countStyle: .file)
                byteProgressText = "\(downloadedStr) of \(totalStr)"
            }

            let posterURL = singleItem.artworkURL(client: client)

            return DownloadSummaryPresentation(
                title: singleItem.title,
                subtitle: byteProgressText ?? (singleItem.status == .queued ? "Queued" : status),
                detailText: detail,
                progress: singleItem.progress,
                itemsRemaining: 1,
                totalItems: 1,
                status: singleItem.status,
                posterImageData: nil,
                posterURL: posterURL,
                isSingleElement: true
            )
        }

        // Case 3: Multiple unrelated elements -> NO POSTER, ONLY THE ICON!
        let overallProgress = active.reduce(0.0) { $0 + $1.progress } / Double(max(active.count, 1))
        let globalStatus = DownloadStatus(items: active)
        let isAllQueued = globalStatus == .queued
        let isConverting = globalStatus == .converting
        let activeItem = active.first(where: { $0.status == .downloading || $0.status == .converting || $0.status == .finalizing }) ?? active.first
        let currentDownloadingTitle: String? = {
            if isAllQueued {
                return "\(totalActiveCount) items queued"
            } else if let activeItem {
                let action = (activeItem.status == .converting || activeItem.status == .finalizing) ? "Converting" : "Downloading"
                return "\(action) \(activeItem.title)"
            } else {
                return "\(totalActiveCount) items"
            }
        }()

        let detail: String = {
            if globalStatus == .failed {
                return "\(totalActiveCount) items left (Failed)"
            } else if isAllQueued {
                return "\(totalActiveCount) items queued"
            } else if isConverting {
                return "\(totalActiveCount) items • Converting"
            } else {
                return "\(totalActiveCount) item\(totalActiveCount == 1 ? "" : "s") left • \(Int(overallProgress * 100))%"
            }
        }()

        let mainTitle = isAllQueued ? "\(totalActiveCount) items queued" : "\(totalActiveCount) items"
        return DownloadSummaryPresentation(
            title: mainTitle,
            subtitle: currentDownloadingTitle,
            detailText: detail,
            progress: overallProgress,
            itemsRemaining: totalActiveCount,
            totalItems: totalItemsCount,
            status: globalStatus,
            posterImageData: nil,
            posterURL: nil,
            isSingleElement: false
        )
    }
}

// MARK: - DownloadItem Artwork Helper

extension DownloadItem {
    func artworkURL(client: JellyfinClient?, libraryViewModel: LibraryViewModel? = nil) -> URL? {
        guard let client else { return nil }
        if item.type == .episode {
            let hasThumb = item.imageTags?.keys.contains("Thumb") == true
            let hasPrimary = item.imageTags?.keys.contains("Primary") == true
            if (hasThumb || hasPrimary), let id = item.id {
                let imageType = hasThumb ? "Thumb" : "Primary"
                return client.itemImageURL(
                    itemID: id,
                    imageType: imageType,
                    parameters: .poster()
                )
            }
            if let id = item.id {
                return client.itemImageURL(
                    itemID: id,
                    parameters: .poster()
                )
            }
            if let libraryViewModel, let url = libraryViewModel.seriesPosterURL(for: item, client: client) {
                return url
            }
            if let directURL = group?.posterURL(client: client) {
                return directURL
            }
            return nil
        } else {
            guard let id = item.id else { return nil }
            let primaryTag = item.imageTags?["Primary"]
            return client.itemImageURL(
                itemID: id,
                parameters: .poster(tag: primaryTag)
            )
        }
    }
}
