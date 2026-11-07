//
//  DownloadsViewModel.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 10/23/26.
//

import Foundation
import Observation
import JellyfinAPI

// MARK: - Downloads View Model

@Observable
@MainActor
final class DownloadsViewModel {
    // MARK: - State

    var initialSeriesID: String?
    var initialSeriesName: String?
    var onBack: (() -> Void)?

    var selectedGroup: ShowDownloadGroup?
    var itemToCancel: DownloadItem?
    var itemToDelete: DownloadItem?
    var groupToCancel: ShowDownloadGroup?
    var showCancelAllAlert: Bool = false
    var isScrolledUnderneath: Bool = false

    // MARK: - Dependencies

    var downloadManager: DownloadManager

    // MARK: - Initializer

    init(
        seriesID: String? = nil,
        seriesName: String? = nil,
        onBack: (() -> Void)? = nil,
        downloadManager: DownloadManager? = nil
    ) {
        self.initialSeriesID = seriesID
        self.initialSeriesName = seriesName
        self.onBack = onBack
        self.downloadManager = downloadManager ?? .shared
    }

    // MARK: - Active Overview Computations

    var allActiveDownloads: [DownloadItem] {
        downloadManager.activeDownloads.sorted { $0.dateAdded < $1.dateAdded }
    }

    var groups: [ShowDownloadGroup] {
        DownloadGrouping.groups(from: allActiveDownloads, completed: downloadManager.completedDownloads)
    }

    var standaloneItems: [DownloadItem] {
        DownloadGrouping.standaloneDownloads(from: allActiveDownloads, groupedIDs: Set(groups.map(\.id)))
    }

    var isSingleGroup: Bool {
        if let first = groups.first, first.isAllQueued {
            return false
        }
        return groups.count == 1 && standaloneItems.isEmpty
    }

    var singleGroup: ShowDownloadGroup? {
        if isSingleGroup {
            return groups.first
        }
        return nil
    }

    // MARK: - Active Show Context

    var activeSeriesID: String? {
        if let initialSeriesID {
            return initialSeriesID
        }
        if let selectedGroup {
            return selectedGroup.id
        }
        if let singleGroup {
            return singleGroup.id
        }
        return nil
    }

    var activeSeriesName: String {
        if let initialSeriesName {
            return initialSeriesName
        }
        if let selectedGroup {
            return selectedGroup.seriesName
        }
        if let singleGroup {
            return singleGroup.seriesName
        }
        return "Downloads"
    }

    var isShowMode: Bool {
        activeSeriesID != nil
    }

    // MARK: - Show Mode Downloads

    var showActiveEpisodes: [DownloadItem] {
        guard let id = activeSeriesID else { return [] }
        return downloadManager.activeDownloads.filter {
            $0.group?.id == id ||
            $0.item.seriesID == id ||
            $0.item.parentBackdropItemID == id ||
            ($0.item.type == .episode && $0.item.seriesName == activeSeriesName)
        }
        .sorted { $0.dateAdded < $1.dateAdded }
    }

    var showCompletedEpisodes: [DownloadItem] {
        guard let id = activeSeriesID else { return [] }
        return downloadManager.completedDownloads.filter {
            $0.group?.id == id ||
            $0.item.seriesID == id ||
            $0.item.parentBackdropItemID == id ||
            ($0.item.type == .episode && $0.item.seriesName == activeSeriesName)
        }
        .sorted { ($0.dateCompleted ?? $0.dateAdded) < ($1.dateCompleted ?? $1.dateAdded) }
    }

    var showGroup: ShowDownloadGroup {
        ShowDownloadGroup(
            id: activeSeriesID ?? "",
            seriesName: activeSeriesName,
            groupInfo: selectedGroup?.groupInfo ?? singleGroup?.groupInfo,
            activeDownloads: showActiveEpisodes,
            completedDownloads: showCompletedEpisodes
        )
    }

    var isCollection: Bool {
        showGroup.representativeItem?.type == .movie || showGroup.representativeItem?.type == .boxSet
    }

    var showOverallProgress: Double {
        let total = showActiveEpisodes.count + showCompletedEpisodes.count
        guard total > 0 else { return 0 }
        let completedProgress = Double(showCompletedEpisodes.count)
        let activeProgress = showActiveEpisodes.reduce(0.0) { $0 + $1.progress }
        return (completedProgress + activeProgress) / Double(total)
    }

    // MARK: - Subtitles & Progress

    var showSubtitle: String? {
        if showGroup.isAllFailed {
            return "Failed"
        } else if showActiveEpisodes.isEmpty {
            return "All downloaded"
        } else if showGroup.isAllQueued && showCompletedEpisodes.isEmpty {
            return "Queued"
        } else {
            let count = showActiveEpisodes.count
            let unit = isCollection ? (count == 1 ? "movie" : "movies") : (count == 1 ? "episode" : "episodes")
            let percentStr = "\(Int(showOverallProgress * 100))%"
            return "\(percentStr) • \(count) \(unit) left"
        }
    }

    var overviewOverallProgress: Double {
        guard !allActiveDownloads.isEmpty else { return 0 }
        let total = allActiveDownloads.reduce(0.0) { $0 + $1.progress }
        return total / Double(allActiveDownloads.count)
    }

    var overviewSubtitle: String? {
        if allActiveDownloads.isEmpty {
            return "No active downloads"
        } else if allActiveDownloads.allSatisfy({ $0.status == .queued }) && overviewOverallProgress == 0 {
            return "Queued"
        } else if allActiveDownloads.count == 1,
                  let single = allActiveDownloads.first,
                  (single.status == .downloading || single.status == .converting),
                  let time = single.estimatedTimeRemaining, time > 0 {
            let cleanTime = single.formattedTimeRemaining.replacingOccurrences(of: " left", with: "")
            return "\(cleanTime) • \(Int(overviewOverallProgress * 100))%"
        } else {
            return "\(Int(overviewOverallProgress * 100))%"
        }
    }

    var currentProgress: Double {
        isShowMode ? showOverallProgress : overviewOverallProgress
    }

    var currentSubtitle: String? {
        isShowMode ? showSubtitle : overviewSubtitle
    }

    var currentTitle: String {
        isShowMode ? activeSeriesName : "Downloads"
    }

    var currentShowCancel: Bool {
        if isShowMode {
            return !showActiveEpisodes.isEmpty
        } else {
            return !allActiveDownloads.isEmpty
        }
    }

    var showTopBarInOverview: Bool {
        (groups.count + standaloneItems.count) > 1 || (groups.first?.isAllQueued == true)
    }

    var canGoBack: Bool {
        if selectedGroup != nil {
            return true
        }
        if initialSeriesID != nil && onBack != nil {
            return true
        }
        return false
    }

    // MARK: - Navigation Actions

    func selectGroup(_ group: ShowDownloadGroup) {
        selectedGroup = group
    }

    func handleBack(dismiss: () -> Void) {
        if selectedGroup != nil {
            selectedGroup = nil
        } else if let onBack {
            onBack()
        } else {
            dismiss()
        }
    }

    // MARK: - Download Management Actions

    func cancelDownload(id: String) {
        downloadManager.cancelDownload(id: id)
    }

    func resumeDownload(id: String, client: JellyfinClient?) {
        downloadManager.resumeDownload(id: id, client: client)
    }

    func deleteDownload(id: String) {
        downloadManager.deleteDownload(id: id)
    }

    func cancelGroup(_ group: ShowDownloadGroup) {
        downloadManager.cancelDownloads(ids: group.activeDownloads.map(\.id))
    }

    func cancelAllActive() {
        if isShowMode {
            downloadManager.cancelDownloads(ids: showActiveEpisodes.map(\.id))
        } else {
            downloadManager.cancelDownloads(ids: downloadManager.activeDownloads.map(\.id))
        }
    }

}
