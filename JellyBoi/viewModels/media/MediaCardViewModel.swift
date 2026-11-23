//
//  MediaCardViewModel.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 9/29/26.
//

import Foundation
import CoreGraphics
import Observation
import JellyfinAPI

@Observable
@MainActor
class MediaCardViewModel {

    var item: BaseItemDto
    var isHovered: Bool = false
    var isProgressReset: Bool = false

    init(item: BaseItemDto) {
        self.item = item
    }

    func updateItem(_ newItem: BaseItemDto) {
        if !isProgressReset,
           let currentTicks = self.item.userData?.playbackPositionTicks, currentTicks > 0,
           (newItem.userData?.playbackPositionTicks == nil || newItem.userData?.playbackPositionTicks == 0) {
            var merged = newItem
            merged.userData = self.item.userData
            self.item = merged
        } else {
            self.item = newItem
        }
    }

    func cardAspectRatio(overrideRatio: CGFloat?) -> CGFloat {
        overrideRatio ?? item.imageAspectRatio
    }

    // MARK: - Playback State Resolution

    func watchProgress(isWatched: Bool? = nil) -> Double? {
        if isProgressReset { return nil }
        let watched = isWatched ?? self.isWatched()
        if watched { return 1.0 }
        if item.type == .series, let seriesID = item.id {
            return item.seriesWatchProgress(allEpisodes: LibraryViewModel.shared.episodes(forSeriesID: seriesID))
        }
        return item.watchProgress
    }

    func isWatched() -> Bool {
        if isProgressReset { return false }
        if item.type == .series, let seriesID = item.id {
            return item.isSeriesWatched(allEpisodes: LibraryViewModel.shared.episodes(forSeriesID: seriesID))
        }
        return item.isWatched
    }

    func isWatching(isWatched: Bool? = nil) -> Bool {
        if isProgressReset { return false }
        let watched = isWatched ?? self.isWatched()
        if watched { return false }
        if item.type == .series, let seriesID = item.id {
            let lib = LibraryViewModel.shared
            return item.isSeriesInProgress(
                allEpisodes: lib.episodes(forSeriesID: seriesID),
                resumeShows: lib.resumeShowIDs.compactMap { lib[$0] }
            )
        }
        return item.isInProgress
    }

    // MARK: - Actions

    func handleResetProgress(
        serverViewModel: ServerViewModel?,
        onResetProgress: (() -> Void)? = nil
    ) {
        Task {
            _ = await serverViewModel?.resetProgress(for: item)
            onResetProgress?()
        }
    }

    func handleProgressResetNotification(resetID: String) {
        if resetID == item.id || (item.seriesID != nil && resetID == item.seriesID) {
            isProgressReset = true
        }
    }

    func handleProgressUpdatedNotification(itemID: String, positionTicks: Int, totalTicks: Int?) {
        if itemID == item.id {
            item.updateProgress(positionTicks: positionTicks, totalTicks: totalTicks)
            isProgressReset = false
        }
    }

    // MARK: - Favorite Management

    func handleToggleFavorite(serverViewModel: ServerViewModel?) {
        guard let serverViewModel, let itemID = item.id else { return }
        let currentFavorite = item.isFavorite
        let newFavorite = !currentFavorite
        item.setFavorite(newFavorite)
        Task {
            let result = await serverViewModel.setFavorite(newFavorite, forItemID: itemID)
            if result == nil {
                item.setFavorite(currentFavorite)
            }
        }
    }

    func handleFavoriteNotification(itemID: String, isFavorite: Bool) {
        if item.id == itemID {
            item.setFavorite(isFavorite)
        }
    }
}
