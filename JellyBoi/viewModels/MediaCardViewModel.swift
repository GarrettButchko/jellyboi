//
//  MediaCardViewModel.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 9/29/26.
//

import SwiftUI
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

    func watchProgress(in libraryViewModel: LibraryViewModel?) -> Double? {
        if isProgressReset { return nil }
        if isWatched(in: libraryViewModel) { return 1.0 }
        if item.type == .series, let seriesID = item.id {
            return item.seriesWatchProgress(allEpisodes: libraryViewModel?.episodes(forSeriesID: seriesID) ?? [])
        }
        return item.watchProgress
    }

    func isWatched(in libraryViewModel: LibraryViewModel?) -> Bool {
        if isProgressReset { return false }
        if item.type == .series, let seriesID = item.id {
            return item.isSeriesWatched(allEpisodes: libraryViewModel?.episodes(forSeriesID: seriesID) ?? [])
        }
        return item.isWatched
    }

    func isWatching(in libraryViewModel: LibraryViewModel?) -> Bool {
        if isProgressReset { return false }
        if isWatched(in: libraryViewModel) { return false }
        if item.type == .series, let seriesID = item.id {
            return item.isSeriesInProgress(
                allEpisodes: libraryViewModel?.episodes(forSeriesID: seriesID) ?? [],
                resumeShows: libraryViewModel?.resumeShows ?? []
            )
        }
        return item.isInProgress
    }

    // MARK: - Actions

    func handleResetProgress(
        serverViewModel: ServerViewModel?,
        onResetProgress: (() -> Void)? = nil
    ) {
        withAnimation(.smooth) {
            isProgressReset = true
        }
        Task {
            await serverViewModel?.resetProgress(for: item) {
                onResetProgress?()
            }
        }
    }

    func handleProgressResetNotification(resetID: String) {
        if resetID == item.id || (item.seriesID != nil && resetID == item.seriesID) {
            withAnimation(.smooth) {
                isProgressReset = true
            }
        }
    }

    func handleProgressUpdatedNotification(itemID: String, positionTicks: Int, totalTicks: Int?) {
        if itemID == item.id {
            let total = totalTicks ?? item.runTimeTicks.map { Int($0) } ?? 0
            let percent = total > 0 ? (Double(positionTicks) / Double(total)) * 100.0 : 0.0
            let isZeroOrPlayed = percent < 1.0 || percent >= 85.0
            if isZeroOrPlayed {
                withAnimation(.smooth(duration: 0.35)) {
                    item.updateProgress(positionTicks: positionTicks, totalTicks: totalTicks)
                    isProgressReset = false
                }
            } else {
                item.updateProgress(positionTicks: positionTicks, totalTicks: totalTicks)
                isProgressReset = false
            }
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
