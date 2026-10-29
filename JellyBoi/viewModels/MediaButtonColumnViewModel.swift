//
//  MediaButtonColumnViewModel.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 9/29/26.
//

import SwiftUI
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
        withAnimation(.smooth) {
            isProgressReset = true
        }
        Task {
            await serverViewModel?.resetProgress(for: item) {
                onResetProgress?()
            }
        }
    }

    func handlePlayTap(
        onPlay: (() -> Void)? = nil,
        onContinueWatching: (() -> Void)? = nil,
        onStartFromBeginning: (() -> Void)? = nil
    ) {
        if !isProgressReset && item.isInProgress {
            onContinueWatching?() ?? onPlay?()
        } else if !isProgressReset && item.isWatched {
            onStartFromBeginning?()
        } else {
            onStartFromBeginning?() ?? onPlay?()
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
            withAnimation(.smooth) {
                item.updateProgress(positionTicks: positionTicks, totalTicks: totalTicks)
                isProgressReset = false
            }
        }
    }
}
