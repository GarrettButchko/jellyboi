//
//  MediaButtonColumnViewModel.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 9/29/26.
//

import Foundation
import Observation
import JellyfinAPI

@Observable
@MainActor
class MediaButtonColumnViewModel {

    var item: BaseItemDto
    var isProgressReset: Bool = false

    init(item: BaseItemDto) {
        self.item = item
    }

    func updateItem(_ newItem: BaseItemDto) {
        self.item = newItem
        self.isProgressReset = false
    }

    // MARK: - Server-derived Playback State

    var progressValue: Double {
        if isProgressReset { return 0.0 }
        return item.isWatched ? 1.0 : (item.watchProgress ?? 0.0)
    }

    // MARK: - Playback Actions

    func handleResetProgress(
        serverViewModel: ServerViewModel?,
        onResetProgress: (() -> Void)? = nil
    ) {
        Task {
            _ = await serverViewModel?.resetProgress(for: item)
            onResetProgress?()
        }
    }

    func handlePlayTap(
        onPlay: (() -> Void)? = nil,
        onContinueWatching: (() -> Void)? = nil,
        onStartFromBeginning: (() -> Void)? = nil
    ) {
        let isWatching = item.type == .series ? (progressValue > 0 && !item.isWatched) : item.isInProgress
        if !isProgressReset && isWatching {
            onContinueWatching?() ?? onPlay?()
        } else if !isProgressReset && item.isWatched {
            onStartFromBeginning?()
        } else {
            onStartFromBeginning?() ?? onPlay?()
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
}
