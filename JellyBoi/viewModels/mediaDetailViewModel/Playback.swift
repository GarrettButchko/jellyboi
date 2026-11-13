//
//  Playback.swift
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

    func playableItem(libraryViewModel: LibraryViewModel?, fromBeginning: Bool = false) -> BaseItemDto {
        var currentItem = displayItem ?? BaseItemDto()
        if currentItem.type == .series || currentItem.type == .boxSet {
            return nextPlayableEpisode(libraryViewModel: libraryViewModel, fromBeginning: fromBeginning) ?? currentItem
        }
        if let id = currentItem.id,
           currentItem.resumePlaybackTicks == 0,
           let matching = libraryViewModel?.movies.first(where: { $0.id == id }) ?? libraryViewModel?.resumeShows.first(where: { $0.id == id }),
           matching.resumePlaybackTicks > 0 {
            currentItem.userData = matching.userData
        }
        return currentItem
    }

    var playbackQueue: [BaseItemDto]? {
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
        serverViewModel: ServerViewModel,
        libraryViewModel: LibraryViewModel
    ) {
        let itemToPlay = playableItem(libraryViewModel: libraryViewModel, fromBeginning: fromBeginning)
        playbackManager.play(
            item: itemToPlay,
            fromBeginning: fromBeginning,
            client: serverViewModel.client,
            userID: serverViewModel.currentUser?.id,
            libraryViewModel: libraryViewModel,
            mediaSourceID: selectedMediaSourceID,
            audioStreamIndex: selectedAudioStreamIndex,
            subtitleStreamIndex: selectedSubtitleStreamIndex,
            maxBitrate: selectedMaxBitrate,
            queue: playbackQueue
        )
    }

    func startPreload(
        playbackManager: PlaybackManager,
        serverViewModel: ServerViewModel,
        libraryViewModel: LibraryViewModel
    ) {
        guard !isPlayDisabled else { return }
        let fromBeginning = displayItem?.isWatched ?? false
        let itemToPlay = playableItem(libraryViewModel: libraryViewModel, fromBeginning: fromBeginning)
        playbackManager.preload(
            item: itemToPlay,
            fromBeginning: fromBeginning,
            client: serverViewModel.client,
            userID: serverViewModel.currentUser?.id,
            libraryViewModel: libraryViewModel,
            mediaSourceID: selectedMediaSourceID,
            audioStreamIndex: selectedAudioStreamIndex,
            subtitleStreamIndex: selectedSubtitleStreamIndex,
            maxBitrate: selectedMaxBitrate,
            queue: playbackQueue
        )
    }

    // MARK: - Server-derived Playback State

    // Everything below reads `BaseItemDto.userData` directly. Nothing is aggregated locally from
    // `episodes` or `collectionItems`: if the Jellyfin server does not report progress for an item,
    // the UI shows none rather than inventing a number that would not match other Jellyfin clients.

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

    func targetPlayableTitle(libraryViewModel: LibraryViewModel? = nil) -> String {
        let target = playableItem(libraryViewModel: libraryViewModel)
        let title = target.contextMenuTitle(includeSeriesName: false)
        return title.isEmpty ? (displayItem?.name ?? "") : title
    }

    func handlePlayTap(
        playbackManager: PlaybackManager,
        serverViewModel: ServerViewModel,
        libraryViewModel: LibraryViewModel
    ) {
        if isPlayDisabled {
            return
        }
        if displayItem?.isWatched ?? false {
            playMedia(
                fromBeginning: true,
                playbackManager: playbackManager,
                serverViewModel: serverViewModel,
                libraryViewModel: libraryViewModel
            )
        } else {
            playMedia(
                fromBeginning: false,
                playbackManager: playbackManager,
                serverViewModel: serverViewModel,
                libraryViewModel: libraryViewModel
            )
        }
    }

    func resetSeriesProgress(serverViewModel: ServerViewModel?) {
        guard let item = displayItem, let itemID = item.id else { return }
        clearProgress(for: itemID)
        for index in episodes.indices {
            episodes[index].clearProgress()
        }
        Task {
            await serverViewModel?.resetProgress(for: item)
            if let client = serverViewModel?.client, let userID = serverViewModel?.currentUser?.id {
                let inProgressOrPlayed = episodes.filter { $0.isWatched || $0.hasProgress }
                for ep in inProgressOrPlayed {
                    if let epID = ep.id {
                        _ = try? await client.send(Paths.markUnplayedItem(itemID: epID, userID: userID))
                    }
                }
            }
        }
    }

    func startSeriesFromBeginning(
        playbackManager: PlaybackManager,
        serverViewModel: ServerViewModel,
        libraryViewModel: LibraryViewModel
    ) {
        resetSeriesProgress(serverViewModel: serverViewModel)

        let firstEpisode = episodes.first(where: { ($0.parentIndexNumber ?? 1) >= 1 && ($0.indexNumber ?? 1) == 1 })
            ?? episodes.first(where: { ($0.parentIndexNumber ?? 1) >= 1 })
            ?? episodes.first
            ?? playableItem(libraryViewModel: libraryViewModel, fromBeginning: true)

        playbackManager.play(
            item: firstEpisode,
            fromBeginning: true,
            client: serverViewModel.client,
            userID: serverViewModel.currentUser?.id,
            libraryViewModel: libraryViewModel,
            mediaSourceID: selectedMediaSourceID,
            audioStreamIndex: selectedAudioStreamIndex,
            subtitleStreamIndex: selectedSubtitleStreamIndex,
            maxBitrate: selectedMaxBitrate,
            queue: !episodes.isEmpty ? episodes : nil
        )
    }

    func resetProgress(serverViewModel: ServerViewModel?) {
        guard let item = displayItem, let itemID = item.id else { return }
        if item.type == .series {
            resetSeriesProgress(serverViewModel: serverViewModel)
            return
        }
        clearProgress(for: itemID)
        Task {
            await serverViewModel?.resetProgress(for: item)
        }
    }

    func clearProgress(for itemID: String) {
        if displayItem?.id == itemID || displayItem?.seriesID == itemID {
            detailedItem?.clearProgress()
            sourceItem?.clearProgress()
        }
        episodes.clearProgress(for: itemID, matchingSeries: true)
        for index in collectionItems.indices {
            if collectionItems[index].id == itemID || itemID == displayItem?.id {
                collectionItems[index].clearProgress()
            }
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
        episodes.updateProgress(for: itemID, positionTicks: positionTicks, totalTicks: totalTicks)
        collectionItems.updateProgress(for: itemID, positionTicks: positionTicks, totalTicks: totalTicks)
    }
}
