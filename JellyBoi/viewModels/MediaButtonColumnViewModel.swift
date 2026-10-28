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

    var contextMenuTitle: String {
        if item.type == .episode {
            var epTitle: String? = nil
            if let season = item.parentIndexNumber, let episode = item.indexNumber {
                epTitle = "S\(season) E\(episode)"
            } else if let episode = item.indexNumber {
                epTitle = "Ep \(episode)"
            }

            let name = item.name
            let series = item.seriesName

            switch (series, epTitle, name) {
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

    func shouldShowOptions(hasOptionsCallback: Bool) -> Bool {
        hasOptionsCallback
    }

    // MARK: - Playback Actions

    func handleStart(onPlay: (() -> Void)? = nil, onStartFromBeginning: (() -> Void)? = nil) {
        if let onStartFromBeginning {
            onStartFromBeginning()
        } else if let onPlay {
            onPlay()
        }
    }

    func handleContinueWatching(onPlay: (() -> Void)? = nil, onContinueWatching: (() -> Void)? = nil) {
        if let onContinueWatching {
            onContinueWatching()
        } else if let onPlay {
            onPlay()
        }
    }

    func handleStartFromBeginning(onStartFromBeginning: (() -> Void)? = nil) {
        onStartFromBeginning?()
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

    func handlePlayTap(
        onPlay: (() -> Void)? = nil,
        onContinueWatching: (() -> Void)? = nil,
        onStartFromBeginning: (() -> Void)? = nil
    ) {
        if !isProgressReset && item.isInProgress {
            handleContinueWatching(onPlay: onPlay, onContinueWatching: onContinueWatching)
        } else if !isProgressReset && item.isWatched {
            handleStartFromBeginning(onStartFromBeginning: onStartFromBeginning)
        } else {
            handleStart(onPlay: onPlay, onStartFromBeginning: onStartFromBeginning)
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
