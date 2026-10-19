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

    var watchProgress: Double? {
        if isProgressReset { return nil }
        return item.watchProgress
    }

    var isWatched: Bool {
        if isProgressReset { return false }
        return item.isWatched
    }

    var isWatching: Bool {
        if isProgressReset { return false }
        return item.isInProgress
    }

    func hasProgress(in libraryViewModel: LibraryViewModel?) -> Bool {
        if isProgressReset { return false }
        if item.hasProgress { return true }
        if item.type == .series, let libraryViewModel {
            return libraryViewModel.resumeShows.contains { $0.seriesID == item.id || $0.id == item.id }
        }
        return false
    }

    func isInProgress(in libraryViewModel: LibraryViewModel?) -> Bool {
        if isProgressReset { return false }
        if isWatched { return false }
        return item.isInProgress || (item.type == .series && hasProgress(in: libraryViewModel))
    }

    var episodeTitle: String? {
        guard item.type == .episode else { return nil }
        if let season = item.parentIndexNumber, let episode = item.indexNumber {
            return "S\(season) E\(episode)"
        }
        if let episode = item.indexNumber {
            return "Ep \(episode)"
        }
        return nil
    }

    var contextMenuTitle: String {
        if item.type == .episode {
            let epNumber = episodeTitle
            let name = item.name
            let series = item.seriesName

            switch (series, epNumber, name) {
            case let (.some(s), .some(e), .some(n)) where !s.isEmpty && !e.isEmpty && !n.isEmpty:
                return "\(s) • \(e): \(n)"
            case let (_, .some(e), .some(n)) where !e.isEmpty && !n.isEmpty:
                return "\(e) • \(n)"
            case let (.some(s), _, .some(n)) where !s.isEmpty && !n.isEmpty:
                return "\(s) • \(n)"
            case let (_, .some(e), _):
                return e
            case let (_, _, .some(n)) where !n.isEmpty:
                return n
            default:
                return "Episode"
            }
        }
        return item.name ?? ""
    }

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

    var isFavorite: Bool {
        item.isFavorite
    }

    func handleToggleFavorite(serverViewModel: ServerViewModel?) {
        guard let serverViewModel, let itemID = item.id else { return }
        let currentFavorite = isFavorite
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
