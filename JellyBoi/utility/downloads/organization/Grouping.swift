//
//  Grouping.swift
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
        status == .converting || status == .finalizing
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
                    return collection.posterURL(client: client)
                }
            } else {
                if let show = libraryViewModel.tvShows.first(where: { $0.id == id }) {
                    return show.posterURL(client: client)
                }
                if let first = representativeItem, let url = first.seriesPosterURL(client: client) {
                    return url
                }
            }
        }
        let tag = representativeItem?.seriesPrimaryImageTag ?? representativeItem?.imageTags?["Primary"]
        return client.itemImageURL(
            itemID: id,
            parameters: .poster(tag: tag)
        )
    }

    public static func formattedTimeRemaining(for items: [DownloadItem]) -> String? {
        let isAllFailed = !items.isEmpty && items.allSatisfy { $0.status == .failed }
        guard !isAllFailed else { return nil }

        guard items.count == 1,
              let activeItem = items.first,
              (activeItem.status == .downloading || activeItem.status == .converting || activeItem.status == .finalizing),
              let time = activeItem.estimatedTimeRemaining, time > 0 else {
            return nil
        }
        return DownloadItem.formattedRemainingTime(from: time)
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
    public let stateKind: DownloadPresentationStateKind
    public let title: String
    public let subtitleLeftText: String
    public let subtitleLeftIcon: String?
    public let subtitleRightText: String?
    public let subtitle: String?
    public let detailText: String?
    public let progress: Double
    public let itemsRemaining: Int
    public let totalItems: Int
    public let status: DownloadStatus
    public let posterImageData: Data?
    public let posterURL: URL?
    public let isSingleElement: Bool
    public let isEpisode: Bool

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
        posterURL: URL? = nil,
        isSingleElement: Bool = true,
        isEpisode: Bool = false
    ) {
        self.stateKind = stateKind
        self.title = title
        self.subtitleLeftText = subtitleLeftText ?? subtitle ?? ""
        self.subtitleLeftIcon = subtitleLeftIcon
        self.subtitleRightText = subtitleRightText
        self.subtitle = subtitle
        self.detailText = detailText
        self.progress = progress
        self.itemsRemaining = itemsRemaining
        self.totalItems = totalItems
        self.status = status
        self.posterImageData = posterImageData
        self.posterURL = posterURL
        self.isSingleElement = isSingleElement
        self.isEpisode = isEpisode
    }

    public func contentState(fallbackPosterData: Data? = nil) -> DownloadActivityAttributes.ContentState {
        DownloadActivityAttributes.ContentState(
            stateKind: stateKind,
            title: title,
            subtitleLeftText: subtitleLeftText,
            subtitleLeftIcon: subtitleLeftIcon,
            subtitleRightText: subtitleRightText,
            subtitle: subtitle,
            detailText: detailText,
            progress: min(max(progress, 0.0), 1.0),
            itemsRemaining: itemsRemaining,
            totalItems: totalItems,
            status: status,
            posterImageData: (stateKind != .multiple) ? (posterImageData ?? fallbackPosterData) : nil,
            isSingleElement: isSingleElement,
            isEpisode: isEpisode
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
            stateKind: stateKind,
            title: title,
            subtitleLeftText: subtitleLeftText,
            subtitleLeftIcon: subtitleLeftIcon,
            subtitleRightText: subtitleRightText,
            subtitle: subtitle,
            detailText: detailText,
            progress: progress,
            itemsRemaining: itemsRemaining,
            totalItems: totalItems,
            status: status,
            posterImageData: posterImageData,
            posterURL: posterURL,
            isSingleElement: isSingleElement,
            isEpisode: isEpisode
        )
    }
}

public enum DownloadGrouping {
    public static func groups(from active: [DownloadItem], completed: [DownloadItem]) -> [ShowDownloadGroup] {
        var groupMap: [String: (name: String, groupInfo: DownloadGroupInfo?, active: [DownloadItem])] = [:]
        for item in active {
            guard let group = item.group else { continue }
            let groupID = group.id
            if var entry = groupMap[groupID] {
                entry.active.append(item)
                groupMap[groupID] = entry
            } else {
                groupMap[groupID] = (name: group.title, groupInfo: group, active: [item])
            }
        }

        var completedGroupMap: [String: [DownloadItem]] = [:]
        for item in completed {
            guard let group = item.group else { continue }
            completedGroupMap[group.id, default: []].append(item)
        }

        var result: [ShowDownloadGroup] = []
        for (groupID, (name, groupInfo, activeItems)) in groupMap {
            let completedItems = completedGroupMap[groupID] ?? []
            result.append(ShowDownloadGroup(
                id: groupID,
                seriesName: name,
                groupInfo: groupInfo,
                activeDownloads: activeItems,
                completedDownloads: completedItems
            ))
        }

        return result.sorted { $0.seriesName.localizedStandardCompare($1.seriesName) == .orderedAscending }
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
                stateKind: .multiple,
                title: "Downloads Complete",
                subtitleLeftText: "100%",
                subtitleLeftIcon: nil,
                subtitleRightText: nil,
                subtitle: "All items ready offline",
                detailText: "100%",
                progress: 1.0,
                itemsRemaining: 0,
                totalItems: completed.count,
                status: .completed,
                posterImageData: nil,
                posterURL: nil,
                isSingleElement: false,
                isEpisode: false
            )
        }

        let computedGroups = groups(from: active, completed: completed)
        let standalones = standaloneDownloads(from: active, groupedIDs: Set(computedGroups.map(\.id)))
        let totalActiveCount = active.count
        let totalItemsCount = active.count + completed.count

        // State 1: A group (could be collection, or series)
        if computedGroups.count == 1 && standalones.isEmpty, let singleGroup = computedGroups.first {
            let progress = singleGroup.overallProgress
            let percent = Int(progress * 100)
            let itemsLeft = singleGroup.episodesLeft
            let itemsLeftText = itemsLeft == 1 ? "1 item left" : "\(itemsLeft) items left"
            let title = singleGroup.seriesName
            let subtitleLeftText = itemsLeftText
            let subtitleLeftIcon = singleGroup.status.icon
            let subtitleRightText = "\(percent)%"
            let posterURL = singleGroup.posterURL(client: client)

            return DownloadSummaryPresentation(
                stateKind: .group,
                title: title,
                subtitleLeftText: subtitleLeftText,
                subtitleLeftIcon: subtitleLeftIcon,
                subtitleRightText: subtitleRightText,
                subtitle: subtitleLeftText,
                detailText: "\(subtitleLeftText) • \(subtitleRightText)",
                progress: progress,
                itemsRemaining: singleGroup.episodesLeft,
                totalItems: singleGroup.totalCount,
                status: singleGroup.status,
                posterImageData: nil,
                posterURL: posterURL,
                isSingleElement: true,
                isEpisode: false
            )
        }

        // State 2: One episode
        if computedGroups.isEmpty && standalones.count == 1, let singleItem = standalones.first, singleItem.item.type == .episode {
            let progress = singleItem.progress
            let percent = Int(progress * 100)
            let title = singleItem.title
            let timeString: String = {
                if singleItem.status == .failed {
                    return "Failed"
                } else if singleItem.status == .queued {
                    return "Queued"
                } else if let time = DownloadItem.formattedRemainingTime(from: singleItem.estimatedTimeRemaining) {
                    return time
                } else if singleItem.status == .converting || singleItem.status == .finalizing {
                    return "Converting"
                } else {
                    return "Downloading"
                }
            }()
            let subtitleLeftText = timeString
            let subtitleLeftIcon = singleItem.statusIcon
            let subtitleRightText = "\(percent)%"
            let posterURL = singleItem.artworkURL(client: client)

            return DownloadSummaryPresentation(
                stateKind: .episode,
                title: title,
                subtitleLeftText: subtitleLeftText,
                subtitleLeftIcon: subtitleLeftIcon,
                subtitleRightText: subtitleRightText,
                subtitle: subtitleLeftText,
                detailText: "\(subtitleLeftText) • \(subtitleRightText)",
                progress: progress,
                itemsRemaining: 1,
                totalItems: 1,
                status: singleItem.status,
                posterImageData: nil,
                posterURL: posterURL,
                isSingleElement: true,
                isEpisode: true
            )
        }

        // State 3: One movie
        if computedGroups.isEmpty && standalones.count == 1, let singleItem = standalones.first {
            let progress = singleItem.progress
            let percent = Int(progress * 100)
            let title = singleItem.title
            let timeString: String = {
                if singleItem.status == .failed {
                    return "Failed"
                } else if singleItem.status == .queued {
                    return "Queued"
                } else if let time = DownloadItem.formattedRemainingTime(from: singleItem.estimatedTimeRemaining) {
                    return time
                } else if singleItem.status == .converting || singleItem.status == .finalizing {
                    return "Converting"
                } else {
                    return "Downloading"
                }
            }()
            let subtitleLeftText = timeString
            let subtitleLeftIcon = singleItem.statusIcon
            let subtitleRightText = "\(percent)%"
            let posterURL = singleItem.artworkURL(client: client)

            return DownloadSummaryPresentation(
                stateKind: .movie,
                title: title,
                subtitleLeftText: subtitleLeftText,
                subtitleLeftIcon: subtitleLeftIcon,
                subtitleRightText: subtitleRightText,
                subtitle: subtitleLeftText,
                detailText: "\(subtitleLeftText) • \(subtitleRightText)",
                progress: progress,
                itemsRemaining: 1,
                totalItems: 1,
                status: singleItem.status,
                posterImageData: nil,
                posterURL: posterURL,
                isSingleElement: true,
                isEpisode: false
            )
        }

        // State 4: Multiple items (e.g. movie and episode, or collection and group, etc.)
        let overallProgress = active.reduce(0.0) { $0 + $1.progress } / Double(max(active.count, 1))
        let percent = Int(overallProgress * 100)
        let globalStatus = DownloadStatus(items: active)
        let title = "\(totalActiveCount) items"
        let subtitleLeftText = "\(percent)%"
        let subtitleLeftIcon: String? = nil
        let subtitleRightText: String? = nil

        return DownloadSummaryPresentation(
            stateKind: .multiple,
            title: title,
            subtitleLeftText: subtitleLeftText,
            subtitleLeftIcon: subtitleLeftIcon,
            subtitleRightText: subtitleRightText,
            subtitle: title,
            detailText: subtitleLeftText,
            progress: overallProgress,
            itemsRemaining: totalActiveCount,
            totalItems: totalItemsCount,
            status: globalStatus,
            posterImageData: nil,
            posterURL: nil,
            isSingleElement: false,
            isEpisode: false
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
            if hasPrimary, let id = item.id {
                let primaryTag = item.imageTags?["Primary"]
                return client.itemImageURL(
                    itemID: id,
                    imageType: "Primary",
                    parameters: .poster(tag: primaryTag)
                )
            }
            if let directURL = group?.posterURL(client: client) {
                return directURL
            }
            if let url = item.seriesPosterURL(client: client) {
                return url
            }
            if hasThumb, let id = item.id {
                let thumbTag = item.imageTags?["Thumb"]
                return client.itemImageURL(
                    itemID: id,
                    imageType: "Thumb",
                    parameters: .poster(tag: thumbTag)
                )
            }
            if let id = item.id {
                return client.itemImageURL(
                    itemID: id,
                    parameters: .poster()
                )
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
