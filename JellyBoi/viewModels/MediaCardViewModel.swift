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

    func updateItem(_ item: BaseItemDto) {
        self.item = item
    }

    func cardAspectRatio(overrideRatio: CGFloat?) -> CGFloat {
        overrideRatio ?? item.imageAspectRatio
    }

    var watchProgress: Double? {
        if isProgressReset { return nil }
        if item.userData?.isPlayed == true { return 1 }
        guard let percent = item.userData?.playedPercentage else { return nil }
        return min(max(percent / 100, 0), 1)
    }

    var isWatched: Bool {
        if isProgressReset { return false }
        if item.userData?.isPlayed == true { return true }
        return (watchProgress ?? 0) >= 0.85
    }

    var isWatching: Bool {
        if isProgressReset { return false }
        return (watchProgress ?? 0) >= 0.01
    }

    func hasProgress(in libraryViewModel: LibraryViewModel?) -> Bool {
        if isProgressReset { return false }
        if let ticks = item.userData?.playbackPositionTicks, ticks > 0 { return true }
        if let percent = item.userData?.playedPercentage, percent >= 1 { return true }
        if item.type == .series, let libraryViewModel {
            return libraryViewModel.resumeShows.contains { $0.seriesID == item.id || $0.id == item.id }
        }
        return false
    }

    func isInProgress(in libraryViewModel: LibraryViewModel?) -> Bool {
        if isProgressReset { return false }
        if isWatched { return false }
        return hasProgress(in: libraryViewModel)
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

    func handleStart(onSelect: () -> Void, onStartFromBeginning: (() -> Void)?) {
        if let onStartFromBeginning {
            onStartFromBeginning()
        } else {
            onSelect()
        }
    }

    func handleContinueWatching(onSelect: () -> Void, onContinueWatching: (() -> Void)?) {
        if let onContinueWatching {
            onContinueWatching()
        } else {
            onSelect()
        }
    }

    func handleStartFromBeginning(onSelect: () -> Void, onStartFromBeginning: (() -> Void)?) {
        if let onStartFromBeginning {
            onStartFromBeginning()
        } else {
            onSelect()
        }
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
}
