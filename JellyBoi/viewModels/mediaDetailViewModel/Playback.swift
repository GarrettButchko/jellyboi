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
        let fromBeginning = isWatched
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

    private var seriesEpisodes: [BaseItemDto] {
        if !episodes.isEmpty { return episodes }
        guard let id = displayItem?.id else { return [] }
        return libraryViewModel?.episodes(forSeriesID: id) ?? []
    }

    var isCollectionWatched: Bool {
        guard displayItem?.type == .boxSet, !collectionItems.isEmpty else { return false }
        return collectionItems.allSatisfy { $0.isWatched }
    }

    var isSeriesWatched: Bool {
        guard displayItem?.type == .series else { return false }
        if let unplayed = displayItem?.userData?.unplayedItemCount, unplayed == 0 { return true }
        if displayItem?.userData?.isPlayed == true { return true }
        let eps = seriesEpisodes
        if !eps.isEmpty {
            return eps.allSatisfy { $0.isWatched }
        }
        return displayItem?.isSeriesWatched(allEpisodes: eps) ?? false
    }

    var isWatched: Bool {
        if displayItem?.type == .boxSet {
            return isCollectionWatched
        }
        if displayItem?.type == .series {
            return isSeriesWatched
        }
        return displayItem?.isWatched ?? false
    }

    func cumulativeProgress(for items: [BaseItemDto]) -> Double {
        BaseItemDto.cumulativeProgress(for: items, allEpisodes: libraryViewModel?.episodes ?? [])
    }

    var hasProgress: Bool {
        if isWatched { return false }
        return (watchProgress ?? 0) > 0
    }

    var isInProgress: Bool {
        if isWatched { return false }
        if displayItem?.type == .boxSet {
            return collectionItems.contains { $0.isWatched || $0.isInProgress }
        }
        if displayItem?.type == .series {
            let eps = seriesEpisodes
            if !eps.isEmpty {
                return eps.contains { $0.isWatched || $0.isInProgress }
            }
            return displayItem?.isSeriesInProgress(
                allEpisodes: eps,
                resumeShows: libraryViewModel?.resumeShows ?? []
            ) ?? false
        }
        return displayItem?.isInProgress ?? false
    }

    var watchProgress: Double? {
        if isWatched { return 1.0 }
        if displayItem?.type == .boxSet {
            if !collectionItems.isEmpty {
                return cumulativeProgress(for: collectionItems)
            }
            return 0.0
        }
        if displayItem?.type == .series {
            let eps = seriesEpisodes
            if !eps.isEmpty {
                return cumulativeProgress(for: eps)
            }
            return displayItem?.seriesWatchProgress(allEpisodes: eps) ?? 0.0
        }
        return displayItem?.watchProgress
    }

    var progressVisible: Bool {
        if displayItem?.type == .boxSet { return false }
        if isWatched { return true }
        guard let wp = watchProgress else { return false }
        return Int(wp * 100) > 0
    }

    var progressValue: Double {
        if isWatched { return 1.0 }
        return watchProgress ?? 0.0
    }

    var percentText: String {
        if isWatched { return "100%" }
        if displayItem?.type == .boxSet || displayItem?.type == .series {
            if let wp = watchProgress {
                return "\(Int(wp * 100))%"
            }
            return "0%"
        }
        return displayItem?.percentText ?? ""
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
        if isWatched {
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
