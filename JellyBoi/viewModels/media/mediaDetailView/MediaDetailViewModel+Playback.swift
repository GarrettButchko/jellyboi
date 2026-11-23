//
//  MediaDetailViewModel+Playback.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 9/2/26.
//

import Foundation
import JellyfinAPI

// MARK: - Playback & Progress State & Actions

extension MediaDetailViewModel {

    enum SeriesConfirmationAlert {
        case startFromBeginning
        case resetProgress
    }

    // MARK: - Next Playable Resolution

    /// Resolves the next playable item ID (episode, movie, or collection child) based on watch/resume state.
    func nextPlayableItem(fromBeginning: Bool = false) -> String? {
        let library = LibraryViewModel.shared
        
        let defaultID = displayItem?.id ?? sourceItemId

        // 1. Single Movie or Episode
        if displayItem?.type == .episode || displayItem?.type == .movie {
            return defaultID
        }

        // 2. Series: Resume episode ID -> Next unplayed episode ID -> First episode ID -> Series ID
        if displayItem?.type == .series  {
            let resolvedEpisodes = episodes.compactMap { library[$0] }
            if let playableID = resolvedEpisodes.nextPlayableID(fromBeginning: fromBeginning) {
                return playableID
            }
            return defaultID
        }

        // 3. BoxSet / Collection: Next unplayed item ID (or next episode ID if that item is a show)
        if displayItem?.type == .boxSet {
            let resolvedCollectionItems: [BaseItemDto] = collectionItems.compactMap { library[$0] }
            if let nextItemID = resolvedCollectionItems.nextPlayableID(fromBeginning: fromBeginning) {
                let nextItem = library[nextItemID]
                if nextItem?.type == .series {
                    if !fromBeginning,
                       let sID = nextItem?.id,
                       let resumeID = library.resumeShowIDs.first(where: { library.parentSeriesId(childId: $0) == sID }) {
                        return resumeID
                    }
                    let matching = library.episodes(forSeriesID: nextItem?.id ?? "")
                        .sorted { a, b in
                            let sA = a.parentIndexNumber ?? 1
                            let sB = b.parentIndexNumber ?? 1
                            if sA != sB { return sA < sB }
                            return (a.indexNumber ?? 1) < (b.indexNumber ?? 1)
                        }
                    if let epID = matching.nextPlayableID(fromBeginning: fromBeginning) {
                        return epID
                    }
                    return nextItem?.id
                }
                return nextItemID
            }
            return displayItem?.id ?? sourceItem?.id ?? sourceItemId
        }

        return displayItem?.id ?? sourceItem?.id ?? sourceItemId
    }

    /// The next playable item ID for this detail view.
    var nextPlayableItem: String? {
        nextPlayableItem(fromBeginning: false)
    }

    /// The item ID of the next playable item (guaranteeing non-empty fallback if available).
    var nextPlayableItemID: String {
        nextPlayableItem ?? sourceItemId ?? ""
    }

    /// Returns the resolved item ready for playback (guaranteeing a fallback BaseItemDto).
    func playableItem(fromBeginning: Bool = false) -> BaseItemDto {
        let library = LibraryViewModel.shared
        if let targetID = nextPlayableItem(fromBeginning: fromBeginning) {
            if let item = library[targetID] {
                var res = item
                if !fromBeginning, res.resumePlaybackTicks == 0, let matching = library[targetID], matching.resumePlaybackTicks > 0 {
                    res.userData = matching.userData
                }
                return res
            }
        }
        var fallback = displayItem ?? sourceItem ?? BaseItemDto()
        if !fromBeginning, let id = fallback.id, fallback.resumePlaybackTicks == 0, let matching = library[id], matching.resumePlaybackTicks > 0 {
            fallback.userData = matching.userData
        }
        return fallback
    }

    var playableItemID: String {
        nextPlayableItemID
    }

    var playbackQueue: [String]? {
        if displayItem?.type == .series, !episodes.isEmpty {
            return episodes
        }
        if displayItem?.type == .boxSet, !collectionItems.isEmpty {
            return collectionItems
        }
        return nil
    }

    func playMedia(
        fromBeginning: Bool,
        playbackManager: PlaybackManager,
        serverViewModel: ServerViewModel
    ) {
        if playbackManager.client == nil {
            playbackManager.client = serverViewModel.client
            playbackManager.userID = serverViewModel.currentUser?.id
        }
        let itemID = nextPlayableItem(fromBeginning: fromBeginning) ?? nextPlayableItemID
        guard !itemID.isEmpty else { return }
        playbackManager.play(
            itemID: itemID,
            playbackInfo: currentPlaybackInfo,
            fromBeginning: fromBeginning,
            queue: playbackQueue
        )
    }

    // MARK: - Server-derived Playback State

    /// True when the server reports progress that has not reached the played threshold.
    var isInProgress: Bool {
        displayItem?.isInProgress ?? false
    }

    /// Whether the progress ring should be shown; always on once the item is finished.
    var progressVisible: Bool {
        displayItem?.isProgressVisible ?? false
    }

    /// Progress ring fill amount, derived from the server's percentage.
    var progressValue: Double {
        Double(displayItem?.progressPercentage ?? 0) / 100.0
    }

    /// Formatted percentage label, e.g. "45%".
    var percentText: String {
        displayItem?.percentText ?? ""
    }

    func targetPlayableTitle() -> String {
        let target = playableItem()
        let title = target.contextMenuTitle(includeSeriesName: false)
        return title.isEmpty ? (displayItem?.name ?? "") : title
    }

    func handlePlayTap(
        playbackManager: PlaybackManager,
        serverViewModel: ServerViewModel
    ) {
        if isPlayDisabled {
            return
        }
        if displayItem?.isWatched ?? false {
            playMedia(
                fromBeginning: true,
                playbackManager: playbackManager,
                serverViewModel: serverViewModel
            )
        } else {
            playMedia(
                fromBeginning: false,
                playbackManager: playbackManager,
                serverViewModel: serverViewModel
            )
        }
    }

    /// Resets watch state on the server. Nothing is cleared locally: the server's response is
    /// broadcast through `.mediaUserDataChanged` and applied by `applyUserData`.
    func resetProgress(serverViewModel: ServerViewModel?) {
        guard let item = displayItem else { return }
        Task {
            let epItems = episodes.compactMap { LibraryViewModel.shared[$0] }
            await serverViewModel?.resetProgress(for: item, episodes: epItems)
        }
    }

    func startSeriesFromBeginning(
        playbackManager: PlaybackManager,
        serverViewModel: ServerViewModel
    ) {
        Task {
            let epItems = episodes.compactMap { LibraryViewModel.shared[$0] }
            if let item = displayItem {
                await serverViewModel.resetProgress(for: item, episodes: epItems)
            }

            let firstEpisode = epItems.first(where: { ($0.parentIndexNumber ?? 1) >= 1 && ($0.indexNumber ?? 1) == 1 })
                ?? epItems.first(where: { ($0.parentIndexNumber ?? 1) >= 1 })
                ?? epItems.first
                ?? playableItem(fromBeginning: true)

            guard let itemID = firstEpisode.id else { return }
            if playbackManager.client == nil {
                playbackManager.client = serverViewModel.client
                playbackManager.userID = serverViewModel.currentUser?.id
            }
            playbackManager.play(
                itemID: itemID,
                playbackInfo: currentPlaybackInfo,
                fromBeginning: true,
                queue: !episodes.isEmpty ? episodes : nil
            )
        }
    }

    func handleProgressUpdated(itemID: String, positionTicks: Int, totalTicks: Int?) {
        if itemID == displayItem?.id {
            if detailedItem?.id == itemID {
                detailedItem?.updateProgress(positionTicks: positionTicks, totalTicks: totalTicks)
            }
            if sourceItem?.id == itemID {
                sourceItem?.updateProgress(positionTicks: positionTicks, totalTicks: totalTicks)
            }
        }
        LibraryViewModel.shared.updateProgress(for: itemID, positionTicks: positionTicks, totalTicks: totalTicks)
    }
}
