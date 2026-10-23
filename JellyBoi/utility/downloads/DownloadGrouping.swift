//
//  DownloadGrouping.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 10/20/26.
//

import Foundation
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

    public var isAllFailed: Bool {
        !activeDownloads.isEmpty && activeDownloads.allSatisfy { $0.status == .failed }
    }

    public var isAllQueued: Bool {
        !activeDownloads.isEmpty && activeDownloads.allSatisfy { $0.status == .queued }
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
        return client.url(with: Paths.getItemImage(
            itemID: id,
            imageType: "Primary",
            parameters: .init(maxWidth: 400, quality: 80)
        ))
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
    public let isCompleted: Bool

    public init(
        title: String,
        subtitle: String? = nil,
        detailText: String? = nil,
        progress: Double,
        itemsRemaining: Int,
        totalItems: Int,
        isCompleted: Bool = false
    ) {
        self.title = title
        self.subtitle = subtitle
        self.detailText = detailText
        self.progress = progress
        self.itemsRemaining = itemsRemaining
        self.totalItems = totalItems
        self.isCompleted = isCompleted
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
        for (groupID, data) in groupMap {
            let completedMatching = completed.filter {
                $0.group?.id == groupID
            }
            result.append(ShowDownloadGroup(
                id: groupID,
                seriesName: data.name,
                groupInfo: data.groupInfo,
                activeDownloads: data.active.sorted { $0.dateAdded < $1.dateAdded },
                completedDownloads: completedMatching.sorted { ($0.dateCompleted ?? $0.dateAdded) < ($1.dateCompleted ?? $1.dateAdded) }
            ))
        }
        return result.sorted {
            let firstA = $0.activeDownloads.map(\.dateAdded).min() ?? .distantPast
            let firstB = $1.activeDownloads.map(\.dateAdded).min() ?? .distantPast
            return firstA < firstB
        }
    }

    public static func standaloneDownloads(from active: [DownloadItem], groupedIDs: Set<String>) -> [DownloadItem] {
        active.filter { item in
            guard let groupID = item.group?.id else { return true }
            return !groupedIDs.contains(groupID)
        }
        .sorted { $0.dateAdded < $1.dateAdded }
    }

    public static func currentPresentation(
        active: [DownloadItem],
        completed: [DownloadItem]
    ) -> DownloadSummaryPresentation {
        guard !active.isEmpty else {
            return DownloadSummaryPresentation(
                title: "Downloads Complete",
                subtitle: "All items downloaded",
                progress: 1.0,
                itemsRemaining: 0,
                totalItems: completed.count,
                isCompleted: true
            )
        }

        let computedGroups = groups(from: active, completed: completed)
        let standalones = standaloneDownloads(from: active, groupedIDs: Set(computedGroups.map(\.id)))
        let totalActiveCount = active.count
        let totalItemsCount = active.count + completed.count

        // Case 1: Exactly 1 group and no standalone items
        if computedGroups.count == 1 && standalones.isEmpty, let singleGroup = computedGroups.first {
            let activeItem = singleGroup.activeDownloads.first
            var subtitleText: String?
            if let activeItem {
                let status = activeItem.statusDetail ?? (activeItem.status == .downloading ? "Downloading" : activeItem.status.rawValue.capitalized)
                subtitleText = "\(activeItem.title) • \(status)"
            }

            var detail: String?
            if singleGroup.episodesLeft == 1,
               let activeItem,
               let time = activeItem.estimatedTimeRemaining, time > 0 {
                let cleanTime = activeItem.formattedTimeRemaining.replacingOccurrences(of: " left", with: "")
                detail = "\(Int(singleGroup.overallProgress * 100))% • \(cleanTime)"
            } else {
                let itemWord = singleGroup.groupInfo?.type == .collection ? (singleGroup.episodesLeft == 1 ? "item" : "items") : (singleGroup.episodesLeft == 1 ? "episode" : "episodes")
                detail = "\(Int(singleGroup.overallProgress * 100))% • \(singleGroup.episodesLeft) \(itemWord) left"
            }

            return DownloadSummaryPresentation(
                title: singleGroup.seriesName,
                subtitle: subtitleText,
                detailText: detail,
                progress: singleGroup.overallProgress,
                itemsRemaining: singleGroup.episodesLeft,
                totalItems: singleGroup.totalCount,
                isCompleted: false
            )
        }

        // Case 2: Exactly 1 standalone item and no groups
        if computedGroups.isEmpty && standalones.count == 1, let singleItem = standalones.first {
            let status = singleItem.statusDetail ?? (singleItem.status == .downloading ? "Downloading" : singleItem.status.rawValue.capitalized)
            var detail: String?
            if let time = singleItem.estimatedTimeRemaining, time > 0 {
                let cleanTime = singleItem.formattedTimeRemaining.replacingOccurrences(of: " left", with: "")
                detail = "\(cleanTime) • \(Int(singleItem.progress * 100))%"
            } else {
                detail = "\(status) • \(Int(singleItem.progress * 100))%"
            }

            var byteProgressText: String?
            if singleItem.totalBytes > 0 {
                let downloadedStr = ByteCountFormatter.string(fromByteCount: singleItem.bytesDownloaded, countStyle: .file)
                let totalStr = ByteCountFormatter.string(fromByteCount: singleItem.totalBytes, countStyle: .file)
                byteProgressText = "\(downloadedStr) of \(totalStr)"
            }

            return DownloadSummaryPresentation(
                title: singleItem.title,
                subtitle: byteProgressText ?? status,
                detailText: detail,
                progress: singleItem.progress,
                itemsRemaining: 1,
                totalItems: 1,
                isCompleted: false
            )
        }

        // Case 3: Multiple groups / mixed items
        let overallProgress = active.reduce(0.0) { $0 + $1.progress } / Double(max(active.count, 1))
        let activeItem = active.first(where: { $0.status == .downloading || $0.status == .converting || $0.status == .finalizing }) ?? active.first
        let currentDownloadingTitle = activeItem.map { "Downloading \($0.title)" }

        let detail = "\(totalActiveCount) item\(totalActiveCount == 1 ? "" : "s") left • \(Int(overallProgress * 100))%"

        return DownloadSummaryPresentation(
            title: "Downloads",
            subtitle: currentDownloadingTitle,
            detailText: detail,
            progress: overallProgress,
            itemsRemaining: totalActiveCount,
            totalItems: totalItemsCount,
            isCompleted: false
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
                return client.url(with: Paths.getItemImage(
                    itemID: id,
                    imageType: imageType,
                    parameters: .init(maxWidth: 400, quality: 80)
                ))
            }
            if let id = item.id {
                return client.url(with: Paths.getItemImage(
                    itemID: id,
                    imageType: "Primary",
                    parameters: .init(maxWidth: 400, quality: 80)
                ))
            }
            if let libraryViewModel, let url = libraryViewModel.seriesPosterURL(for: item, client: client) {
                return url
            }
            if let directURL = group?.posterURL(client: client) {
                return directURL
            }
            return nil
        } else {
            if let libraryViewModel, let url = libraryViewModel.posterURL(for: item, client: client) {
                return url
            }
            if let id = item.id {
                return client.url(with: Paths.getItemImage(
                    itemID: id,
                    imageType: "Primary",
                    parameters: .init(maxWidth: 400, quality: 80)
                ))
            }
            if let directURL = group?.posterURL(client: client) {
                return directURL
            }
            return nil
        }
    }
}

