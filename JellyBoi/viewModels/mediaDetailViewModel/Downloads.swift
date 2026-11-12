//
//  Downloads.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 9/2/26.
//

import Foundation
import JellyfinAPI

// MARK: - Download State & Actions

extension MediaDetailViewModel {

    enum DownloadAlertAction {
        case cancel
        case delete
    }

    func isShowFullyDownloaded(downloadManager: DownloadManager, libraryViewModel: LibraryViewModel?) -> Bool {
        guard let item = displayItem, item.type == .series, let showID = item.id else { return false }

        if !episodes.isEmpty {
            return episodes.allSatisfy { ep in
                guard let epID = ep.id else { return false }
                return downloadManager.isDownloaded(id: epID)
            }
        }

        let total = item.recursiveItemCount ?? (libraryViewModel?.tvShows.first(where: { $0.id == showID })?.recursiveItemCount)
        if let total, total > 0 {
            let downloadedCount = downloadManager.completedDownloads.filter {
                $0.item.seriesID == showID || $0.item.parentBackdropItemID == showID
            }.count
            return downloadedCount >= total
        }

        return false
    }

    func isShowDownloading(downloadManager: DownloadManager) -> Bool {
        guard let item = displayItem, item.type == .series, let showID = item.id else { return false }
        return downloadManager.activeDownloads.contains(where: { $0.group?.id == showID })
    }

    func isCollectionFullyDownloaded(downloadManager: DownloadManager) -> Bool {
        guard let item = displayItem, item.type == .boxSet, let _ = item.id else { return false }
        guard !collectionItems.isEmpty else { return false }
        return collectionItems.allSatisfy { ci in
            guard let id = ci.id else { return false }
            return downloadManager.isDownloaded(id: id)
        }
    }

    func isCollectionDownloading(downloadManager: DownloadManager) -> Bool {
        guard let item = displayItem, item.type == .boxSet, let collectionID = item.id else { return false }
        return downloadManager.activeDownloads.contains(where: { $0.group?.id == collectionID })
    }

    func collectionDownloadProgress(downloadManager: DownloadManager) -> Double {
        guard let item = displayItem, item.type == .boxSet, let collectionID = item.id else { return 0 }
        let downloading = downloadManager.activeDownloads.filter {
            $0.group?.id == collectionID
        }
        guard !downloading.isEmpty else { return 0 }

        let completed = downloadManager.completedDownloads.filter {
            $0.group?.id == collectionID
        }
        let totalCount = downloading.count + completed.count
        guard totalCount > 0 else { return 0 }

        let totalProgress = Double(completed.count) + downloading.reduce(0.0) { $0 + $1.progress }
        return totalProgress / Double(totalCount)
    }

    func episodesLeft(downloadManager: DownloadManager) -> Int? {
        guard let item = displayItem, item.type == .series, let showID = item.id else { return nil }
        let count = downloadManager.activeDownloads.filter {
            $0.group?.id == showID
        }.count
        return count > 0 ? count : nil
    }

    func showDownloadProgress(downloadManager: DownloadManager) -> Double {
        guard let item = displayItem, item.type == .series, let showID = item.id else { return 0 }

        let downloading = downloadManager.activeDownloads.filter {
            $0.group?.id == showID
        }
        guard !downloading.isEmpty else { return 0 }

        let completed = downloadManager.completedDownloads.filter {
            $0.group?.id == showID
        }
        let totalCount = downloading.count + completed.count
        guard totalCount > 0 else { return 0 }

        let totalProgress = Double(completed.count) + downloading.reduce(0.0) { $0 + $1.progress }
        return totalProgress / Double(totalCount)
    }

    func isDetailDownloaded(downloadManager: DownloadManager, libraryViewModel: LibraryViewModel?) -> Bool {
        if displayItem?.type == .series {
            return isShowFullyDownloaded(downloadManager: downloadManager, libraryViewModel: libraryViewModel)
        } else if displayItem?.type == .boxSet {
            return isCollectionFullyDownloaded(downloadManager: downloadManager)
        }
        let playable = playableItem(libraryViewModel: libraryViewModel)
        return downloadManager.isDownloaded(id: playable.id ?? "")
    }

    func isDetailDownloading(downloadManager: DownloadManager) -> Bool {
        if displayItem?.type == .series {
            return isShowDownloading(downloadManager: downloadManager)
        } else if displayItem?.type == .boxSet {
            return isCollectionDownloading(downloadManager: downloadManager)
        }
        let playable = playableItem(libraryViewModel: nil)
        return downloadManager.isDownloading(id: playable.id ?? "")
    }

    func detailDownloadProgress(downloadManager: DownloadManager, libraryViewModel: LibraryViewModel?) -> Double {
        if displayItem?.type == .series {
            return showDownloadProgress(downloadManager: downloadManager)
        } else if displayItem?.type == .boxSet {
            return collectionDownloadProgress(downloadManager: downloadManager)
        }
        let playable = playableItem(libraryViewModel: libraryViewModel)
        return downloadManager.progress(for: playable.id ?? "") ?? 0.0
    }

    @discardableResult
    func handleDownloadTap(
        downloadManager: DownloadManager,
        client: JellyfinClient?,
        libraryViewModel: LibraryViewModel?
    ) -> DownloadAlertAction? {
        let action: DownloadAlertAction?
        if displayItem?.type == .series {
            if isShowFullyDownloaded(downloadManager: downloadManager, libraryViewModel: libraryViewModel) {
                action = .delete
            } else if isShowDownloading(downloadManager: downloadManager) {
                action = .cancel
            } else if let client {
                let uncompletedEpisodes = episodes.filter { ep in
                    guard let epID = ep.id else { return false }
                    return !downloadManager.isDownloaded(id: epID) && !downloadManager.isDownloading(id: epID)
                }
                let groupInfo = DownloadGroupInfo(
                    id: displayItem?.id ?? "",
                    title: displayItem?.name ?? "Show",
                    type: .show,
                    primaryImageTag: displayItem?.imageTags?["Primary"]
                )
                downloadManager.startDownloads(items: uncompletedEpisodes, client: client, group: groupInfo)
                action = nil
            } else {
                action = nil
            }
        } else if displayItem?.type == .boxSet {
            if isCollectionFullyDownloaded(downloadManager: downloadManager) {
                action = .delete
            } else if isCollectionDownloading(downloadManager: downloadManager) {
                action = .cancel
            } else if let client {
                let collectionID = displayItem?.id ?? ""
                let collectionName = displayItem?.name ?? "Collection"
                let groupInfo = DownloadGroupInfo(
                    id: collectionID,
                    title: collectionName,
                    type: .collection,
                    primaryImageTag: displayItem?.imageTags?["Primary"]
                )
                let startItems: ([BaseItemDto]) -> Void = { items in
                    let uncompletedItems: [BaseItemDto] = items.compactMap { item in
                        guard let itemID = item.id, !downloadManager.isDownloaded(id: itemID), !downloadManager.isDownloading(id: itemID) else { return nil }
                        return item
                    }
                    downloadManager.startDownloads(items: uncompletedItems, client: client, group: groupInfo)
                }

                if collectionItems.isEmpty {
                    Task {
                        await self.loadCollectionItems(client: client, userID: nil)
                        startItems(self.collectionItems.elements)
                    }
                } else {
                    startItems(collectionItems.elements)
                }
                action = nil
            } else {
                action = nil
            }
        } else {
            let playable = playableItem(libraryViewModel: libraryViewModel)
            if let itemID = playable.id {
                if downloadManager.isDownloaded(id: itemID) {
                    action = .delete
                } else if downloadManager.isDownloading(id: itemID) {
                    action = .cancel
                } else if let client {
                    downloadManager.startDownload(item: playable, client: client, group: nil)
                    action = nil
                } else {
                    action = nil
                }
            } else {
                action = nil
            }
        }
        self.downloadAlertAction = action
        return action
    }

    func cancelDownload(downloadManager: DownloadManager) {
        if displayItem?.type == .series {
            guard let showID = displayItem?.id else { return }
            let idsToCancel = downloadManager.activeDownloads
                .filter { $0.group?.id == showID }
                .map(\.id)
            downloadManager.cancelDownloads(ids: idsToCancel)
        } else if displayItem?.type == .boxSet {
            guard let collectionID = displayItem?.id else { return }
            let idsToCancel = downloadManager.activeDownloads
                .filter { $0.group?.id == collectionID }
                .map(\.id)
            downloadManager.cancelDownloads(ids: idsToCancel)
        } else if let itemID = playableItem(libraryViewModel: nil).id {
            downloadManager.cancelDownload(id: itemID)
        }
    }

    func deleteDownload(downloadManager: DownloadManager) {
        if displayItem?.type == .series {
            guard let showID = displayItem?.id else { return }
            let episodeIDs = Set(episodes.compactMap(\.id))
            let idsToDelete = downloadManager.completedDownloads
                .filter {
                    $0.group?.id == showID ||
                    $0.item.seriesID == showID ||
                    $0.item.parentBackdropItemID == showID ||
                    episodeIDs.contains($0.id)
                }
                .map(\.id)
            downloadManager.deleteDownloads(ids: idsToDelete)
        } else if displayItem?.type == .boxSet {
            guard let collectionID = displayItem?.id else { return }
            let collectionItemIDs = Set(collectionItems.compactMap(\.id))
            let idsToDelete = downloadManager.completedDownloads
                .filter {
                    $0.group?.id == collectionID ||
                    collectionItemIDs.contains($0.id)
                }
                .map(\.id)
            downloadManager.deleteDownloads(ids: idsToDelete)
        } else if let itemID = playableItem(libraryViewModel: nil).id {
            downloadManager.deleteDownload(id: itemID)
        }
    }

    func downloadAlertItemName(libraryViewModel: LibraryViewModel?) -> String {
        if displayItem?.type == .series || displayItem?.type == .boxSet {
            return displayItem?.name ?? "this item"
        }
        let playable = playableItem(libraryViewModel: libraryViewModel)
        return playable.name ?? "this item"
    }
}
