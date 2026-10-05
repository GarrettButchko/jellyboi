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

    var watchProgress: Double? {
        if isProgressReset { return nil }
        if item.userData?.isPlayed == true { return 1.0 }
        guard let percent = item.userData?.playedPercentage else { return nil }
        return min(max(percent / 100.0, 0), 1.0)
    }

    var isWatched: Bool {
        if isProgressReset { return false }
        if item.userData?.isPlayed == true { return true }
        return (watchProgress ?? 0) >= 0.85
    }

    var hasProgress: Bool {
        if isProgressReset { return false }
        if let ticks = item.userData?.playbackPositionTicks, ticks > 0 { return true }
        if let percent = item.userData?.playedPercentage, percent >= 1 { return true }
        return false
    }

    var isInProgress: Bool {
        if isProgressReset { return false }
        if isWatched { return false }
        return hasProgress
    }

    var isUnwatched: Bool {
        !isInProgress && !isWatched
    }

    var progressVisible: Bool {
        isInProgress || isWatched
    }

    var progressValue: Double {
        if isWatched { return 1.0 }
        return watchProgress ?? 0.0
    }

    var percentText: String {
        "\(Int(progressValue * 100))%"
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
        guard hasOptionsCallback else { return false }
        return item.type != .series && item.type != .boxSet
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
        if isInProgress {
            handleContinueWatching(onPlay: onPlay, onContinueWatching: onContinueWatching)
        } else if isWatched {
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
