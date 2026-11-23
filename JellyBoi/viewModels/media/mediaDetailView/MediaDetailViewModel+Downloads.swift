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

    var isShowFullyDownloaded: Bool {
        isShowFullyDownloaded(downloadManager: nil)
    }

    func isShowFullyDownloaded(downloadManager: DownloadManager? = nil) -> Bool {
        let dm = downloadManager ?? self.downloadManager
        guard let item = displayItem, item.type == .series, let showID = item.id else { return false }

        if !episodes.isEmpty {
            return episodes.allSatisfy { epID in
                dm.isDownloaded(id: epID)
            }
        }

        let total = item.recursiveItemCount ?? (library[showID]?.recursiveItemCount)
        if let total, total > 0 {
            let downloadedCount = dm.completedDownloads.filter {
                $0.item.seriesID == showID || $0.item.parentBackdropItemID == showID
            }.count
            return downloadedCount >= total
        }

        return false
    }

    var isShowDownloading: Bool {
        isShowDownloading(downloadManager: nil)
    }

    func isShowDownloading(downloadManager: DownloadManager? = nil) -> Bool {
        let dm = downloadManager ?? self.downloadManager
        guard let item = displayItem, item.type == .series, let showID = item.id else { return false }
        return dm.activeDownloads.contains(where: { $0.group?.id == showID })
    }

    var isCollectionFullyDownloaded: Bool {
        isCollectionFullyDownloaded(downloadManager: nil)
    }

    func isCollectionFullyDownloaded(downloadManager: DownloadManager? = nil) -> Bool {
        let dm = downloadManager ?? self.downloadManager
        guard let item = displayItem, item.type == .boxSet, let _ = item.id else { return false }
        guard !collectionItems.isEmpty else { return false }
        return collectionItems.allSatisfy { id in
            dm.isDownloaded(id: id)
        }
    }

    var isCollectionDownloading: Bool {
        isCollectionDownloading(downloadManager: nil)
    }

    func isCollectionDownloading(downloadManager: DownloadManager? = nil) -> Bool {
        let dm = downloadManager ?? self.downloadManager
        guard let item = displayItem, item.type == .boxSet, let collectionID = item.id else { return false }
        return dm.activeDownloads.contains(where: { $0.group?.id == collectionID })
    }

    var collectionDownloadProgress: Double {
        collectionDownloadProgress(downloadManager: nil)
    }

    func collectionDownloadProgress(downloadManager: DownloadManager? = nil) -> Double {
        let dm = downloadManager ?? self.downloadManager
        guard let item = displayItem, item.type == .boxSet, let collectionID = item.id else { return 0 }
        let downloading = dm.activeDownloads.filter {
            $0.group?.id == collectionID
        }
        guard !downloading.isEmpty else { return 0 }

        let completed = dm.completedDownloads.filter {
            $0.group?.id == collectionID
        }
        let totalCount = downloading.count + completed.count
        guard totalCount > 0 else { return 0 }

        let totalProgress = Double(completed.count) + downloading.reduce(0.0) { $0 + $1.progress }
        return totalProgress / Double(totalCount)
    }

    var episodesLeft: Int? {
        episodesLeft(downloadManager: nil)
    }

    func episodesLeft(downloadManager: DownloadManager? = nil) -> Int? {
        let dm = downloadManager ?? self.downloadManager
        guard let item = displayItem, item.type == .series, let showID = item.id else { return nil }
        let count = dm.activeDownloads.filter {
            $0.group?.id == showID
        }.count
        return count > 0 ? count : nil
    }

    var showDownloadProgress: Double {
        showDownloadProgress(downloadManager: nil)
    }

    func showDownloadProgress(downloadManager: DownloadManager? = nil) -> Double {
        let dm = downloadManager ?? self.downloadManager
        guard let item = displayItem, item.type == .series, let showID = item.id else { return 0 }

        let downloading = dm.activeDownloads.filter {
            $0.group?.id == showID
        }
        guard !downloading.isEmpty else { return 0 }

        let completed = dm.completedDownloads.filter {
            $0.group?.id == showID
        }
        let totalCount = downloading.count + completed.count
        guard totalCount > 0 else { return 0 }

        let totalProgress = Double(completed.count) + downloading.reduce(0.0) { $0 + $1.progress }
        return totalProgress / Double(totalCount)
    }

    var isDetailDownloaded: Bool {
        isDetailDownloaded(downloadManager: nil)
    }

    func isDetailDownloaded(downloadManager: DownloadManager? = nil) -> Bool {
        let dm = downloadManager ?? self.downloadManager
        if displayItem?.type == .series {
            return isShowFullyDownloaded(downloadManager: dm)
        } else if displayItem?.type == .boxSet {
            return isCollectionFullyDownloaded(downloadManager: dm)
        }
        let playable = playableItem()
        return dm.isDownloaded(id: playable.id ?? "")
    }

    var isDetailDownloading: Bool {
        isDetailDownloading(downloadManager: nil)
    }

    func isDetailDownloading(downloadManager: DownloadManager? = nil) -> Bool {
        let dm = downloadManager ?? self.downloadManager
        if displayItem?.type == .series {
            return isShowDownloading(downloadManager: dm)
        } else if displayItem?.type == .boxSet {
            return isCollectionDownloading(downloadManager: dm)
        }
        let playable = playableItem()
        return dm.isDownloading(id: playable.id ?? "")
    }

    var detailDownloadProgress: Double {
        detailDownloadProgress(downloadManager: nil)
    }

    func detailDownloadProgress(downloadManager: DownloadManager? = nil) -> Double {
        let dm = downloadManager ?? self.downloadManager
        if displayItem?.type == .series {
            return showDownloadProgress(downloadManager: dm)
        } else if displayItem?.type == .boxSet {
            return collectionDownloadProgress(downloadManager: dm)
        }
        let playable = playableItem()
        return dm.progress(for: playable.id ?? "") ?? 0.0
    }

    @discardableResult
    func handleDownloadTap(
        downloadManager: DownloadManager? = nil,
        client: JellyfinClient? = nil
    ) -> DownloadAlertAction? {
        let dm = downloadManager ?? self.downloadManager
        let currentClient = client ?? self.client ?? serverViewModel?.client
        let action: DownloadAlertAction?
        if displayItem?.type == .series {
            if isShowFullyDownloaded(downloadManager: dm) {
                action = .delete
            } else if isShowDownloading(downloadManager: dm) {
                action = .cancel
            } else if let currentClient {
                let uncompletedEpisodes: [BaseItemDto] = episodes.compactMap { epID in
                    guard !dm.isDownloaded(id: epID) && !dm.isDownloading(id: epID) else { return nil }
                    return library[epID]
                }
                let groupInfo = DownloadGroupInfo(
                    id: displayItem?.id ?? "",
                    title: displayItem?.name ?? "Show",
                    type: .show,
                    primaryImageTag: displayItem?.imageTags?["Primary"]
                )
                dm.startDownloads(items: uncompletedEpisodes, client: currentClient, group: groupInfo)
                action = nil
            } else {
                action = nil
            }
        } else if displayItem?.type == .boxSet {
            if isCollectionFullyDownloaded(downloadManager: dm) {
                action = .delete
            } else if isCollectionDownloading(downloadManager: dm) {
                action = .cancel
            } else if let currentClient {
                let collectionID = displayItem?.id ?? ""
                let collectionName = displayItem?.name ?? "Collection"
                let groupInfo = DownloadGroupInfo(
                    id: collectionID,
                    title: collectionName,
                    type: .collection,
                    primaryImageTag: displayItem?.imageTags?["Primary"]
                )
                let startItems: ([String]) -> Void = { ids in
                    let uncompletedItems: [BaseItemDto] = ids.compactMap { itemID in
                        guard !dm.isDownloaded(id: itemID), !dm.isDownloading(id: itemID) else { return nil }
                        return self.library[itemID]
                    }
                    dm.startDownloads(items: uncompletedItems, client: currentClient, group: groupInfo)
                }

                if collectionItems.isEmpty {
                    Task {
                        await self.loadCollectionItems(client: currentClient, userID: nil)
                        startItems(self.collectionItems)
                    }
                } else {
                    startItems(collectionItems)
                }
                action = nil
            } else {
                action = nil
            }
        } else {
            let playable = playableItem()
            if let itemID = playable.id {
                if dm.isDownloaded(id: itemID) {
                    action = .delete
                } else if dm.isDownloading(id: itemID) {
                    action = .cancel
                } else if let currentClient {
                    dm.startDownload(item: playable, client: currentClient, group: nil)
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

    func cancelDownload(downloadManager: DownloadManager? = nil) {
        let dm = downloadManager ?? self.downloadManager
        if displayItem?.type == .series {
            guard let showID = displayItem?.id else { return }
            let idsToCancel = dm.activeDownloads
                .filter { $0.group?.id == showID }
                .map(\.id)
            dm.cancelDownloads(ids: idsToCancel)
        } else if displayItem?.type == .boxSet {
            guard let collectionID = displayItem?.id else { return }
            let idsToCancel = dm.activeDownloads
                .filter { $0.group?.id == collectionID }
                .map(\.id)
            dm.cancelDownloads(ids: idsToCancel)
        } else if let itemID = playableItem().id {
            dm.cancelDownload(id: itemID)
        }
    }

    func deleteDownload(downloadManager: DownloadManager? = nil) {
        let dm = downloadManager ?? self.downloadManager
        if displayItem?.type == .series {
            guard let showID = displayItem?.id else { return }
            let episodeIDs = Set(episodes)
            let idsToDelete = dm.completedDownloads
                .filter {
                    $0.group?.id == showID ||
                    $0.item.seriesID == showID ||
                    $0.item.parentBackdropItemID == showID ||
                    episodeIDs.contains($0.id)
                }
                .map(\.id)
            dm.deleteDownloads(ids: idsToDelete)
        } else if displayItem?.type == .boxSet {
            guard let collectionID = displayItem?.id else { return }
            let collectionItemIDs = Set(collectionItems)
            let idsToDelete = dm.completedDownloads
                .filter {
                    $0.group?.id == collectionID ||
                    collectionItemIDs.contains($0.id)
                }
                .map(\.id)
            dm.deleteDownloads(ids: idsToDelete)
        } else if let itemID = playableItem().id {
            dm.deleteDownload(id: itemID)
        }
    }

    func downloadAlertItemName() -> String {
        if displayItem?.type == .series || displayItem?.type == .boxSet {
            return displayItem?.name ?? "this item"
        }
        let playable = playableItem()
        return playable.name ?? "this item"
    }
}
