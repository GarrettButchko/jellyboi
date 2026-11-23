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

    private let library: LibraryViewModel
    private weak var serverViewModel: ServerViewModel?

    init(
        item: BaseItemDto,
        library: LibraryViewModel? = nil,
        serverViewModel: ServerViewModel? = nil
    ) {
        self.item = item
        self.library = library ?? .shared
        self.serverViewModel = serverViewModel
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
            return item.seriesWatchProgress(allEpisodes: library.episodes(forSeriesID: seriesID))
        }
        return item.watchProgress
    }

    func isWatched() -> Bool {
        if isProgressReset { return false }
        if item.type == .series, let seriesID = item.id {
            return item.isSeriesWatched(allEpisodes: library.episodes(forSeriesID: seriesID))
        }
        return item.isWatched
    }

    func isWatching(isWatched: Bool? = nil) -> Bool {
        if isProgressReset { return false }
        let watched = isWatched ?? self.isWatched()
        if watched { return false }
        if item.type == .series, let seriesID = item.id {
            return item.isSeriesInProgress(
                allEpisodes: library.episodes(forSeriesID: seriesID),
                resumeShows: library.resumeShowIDs.compactMap { library[$0] }
            )
        }
        return item.isInProgress
    }

    // MARK: - Actions

    func handleResetProgress(
        serverViewModel: ServerViewModel? = nil,
        onResetProgress: (() -> Void)? = nil
    ) {
        let svm = serverViewModel ?? self.serverViewModel ?? ServerViewModel.shared
        Task {
            _ = await svm.resetProgress(for: item)
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

    func handleToggleFavorite(serverViewModel: ServerViewModel? = nil) {
        guard let itemID = item.id else { return }
        let svm = serverViewModel ?? self.serverViewModel ?? ServerViewModel.shared
        let currentFavorite = item.isFavorite
        let newFavorite = !currentFavorite
        item.setFavorite(newFavorite)
        Task {
            let result = await svm.setFavorite(newFavorite, forItemID: itemID)
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
