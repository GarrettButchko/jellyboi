//
//  Episodes.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 9/2/26.
//

import Foundation
import JellyfinAPI

// MARK: - Seasons, Episodes & Collections

extension MediaDetailViewModel {

    // MARK: - Seasons Derivation

    static func deriveSeasons(from episodes: [BaseItemDto], seriesID: String? = nil) -> [BaseItemDto] {
        var seasonsDict: [Int: (id: String?, name: String?)] = [:]
        for ep in episodes {
            let seasonNum = ep.parentIndexNumber ?? 1
            guard seasonNum > 0 else { continue }
            if let existing = seasonsDict[seasonNum] {
                let id = existing.id ?? ep.seasonID
                let name = existing.name ?? ep.seasonName
                seasonsDict[seasonNum] = (id, name)
            } else {
                seasonsDict[seasonNum] = (ep.seasonID, ep.seasonName)
            }
        }

        return seasonsDict.keys.sorted().map { sNum in
            let info = seasonsDict[sNum]
            let sID = info?.id ?? (seriesID != nil ? "\(seriesID!)-season-\(sNum)" : "season-\(sNum)")
            let sName = info?.name ?? "Season \(sNum)"
            return BaseItemDto(
                id: sID,
                indexNumber: sNum,
                name: sName,
                parentIndexNumber: sNum,
                type: .season
            )
        }
    }

    func loadSeasonsAndEpisodes(client: JellyfinClient, userID: String?) async {
        guard let seriesID = sourceItem?.id else {
            isLoadingEpisodes = false
            return
        }
        isLoadingEpisodes = true
        defer { isLoadingEpisodes = false }

        // 1. Fetch seasons and sort them off the main actor
        let sortedSeasons = await Task.detached(priority: .userInitiated) { () -> [BaseItemDto] in
            let seasonResult = await client.fetchSeasonsOrEmpty(seriesID: seriesID, userID: userID)

            // Filter out specials and missing-season placeholders
            let filtered = seasonResult.filter { season in
                let num = season.indexNumber ?? season.parentIndexNumber ?? 0
                guard num != 0 else { return false }
                return season.type == .season
            }
            let sorted = (filtered.isEmpty ? seasonResult : filtered).sorted {
                let s0 = $0.indexNumber ?? $0.parentIndexNumber ?? 0
                let s1 = $1.indexNumber ?? $1.parentIndexNumber ?? 0
                return s0 < s1
            }
            return sorted
        }.value

        guard !Task.isCancelled else { return }

        // Publish seasons immediately so the season picker appears without waiting for episodes
        if !sortedSeasons.isEmpty {
            Self.seasonsCache[seriesID] = sortedSeasons
            self.seasons = sortedSeasons
            if !seasons.indices.contains(selectedSeasonIndex) {
                selectedSeasonIndex = 0
            }
        }

        guard !sortedSeasons.isEmpty else { return }

        // 2. Fetch all seasons' episodes in parallel off the main actor
        var seasonNumberMap: [String: Int] = [:]
        for season in sortedSeasons {
            if let id = season.id {
                seasonNumberMap[id] = season.indexNumber ?? season.parentIndexNumber ?? 1
            }
        }

        let sortedEpisodes = await Task.detached(priority: .userInitiated) { () -> [BaseItemDto] in
            let allEpisodes = await withTaskGroup(of: (Int, [BaseItemDto]).self) { group in
                for (index, season) in sortedSeasons.enumerated() {
                    group.addTask {
                        let seasonNum = season.indexNumber ?? season.parentIndexNumber
                        let eps = await client.fetchEpisodesOrEmpty(
                            seriesID: seriesID,
                            seasonNumber: seasonNum,
                            userID: userID
                        )
                        return (index, eps)
                    }
                }
                var dict: [Int: [BaseItemDto]] = [:]
                for await (index, eps) in group {
                    dict[index] = eps
                }
                return dict.sorted { $0.key < $1.key }.map(\.value)
            }

            return allEpisodes.flatMap { $0 }.sorted { a, b in
                let sA = a.parentIndexNumber ?? (a.seasonID.flatMap { seasonNumberMap[$0] }) ?? 1
                let sB = b.parentIndexNumber ?? (b.seasonID.flatMap { seasonNumberMap[$0] }) ?? 1
                if sA != sB {
                    return sA < sB
                }
                let eA = a.indexNumber ?? 1
                let eB = b.indexNumber ?? 1
                if eA != eB {
                    return eA < eB
                }
                return (a.premiereDate ?? .distantPast) < (b.premiereDate ?? .distantPast)
            }
        }.value

        guard !Task.isCancelled else { return }

        Self.episodesCache[seriesID] = sortedEpisodes

        self.episodes = sortedEpisodes

        if !hasInitialEpisodeScrolled {
            if let nextEp = nextPlayableEpisode(libraryViewModel: libraryViewModel),
               let sIdx = seasonIndex(for: nextEp) {
                selectedSeasonIndex = sIdx
            } else {
                selectedSeasonIndex = 0
            }
        } else if !seasons.indices.contains(selectedSeasonIndex) {
            selectedSeasonIndex = 0
        }
    }

    func selectSeason(_ index: Int, client: JellyfinClient? = nil, userID: String? = nil) async {
        guard seasons.indices.contains(index) else { return }
        selectedSeasonIndex = index
    }

    func seasonNumber(for episode: BaseItemDto) -> Int {
        if let p = episode.parentIndexNumber { return p }
        if let sID = episode.seasonID,
           let s = seasons.first(where: { $0.id == sID }) {
            return s.indexNumber ?? s.parentIndexNumber ?? 1
        }
        return 1
    }

    func seasonIndex(for episode: BaseItemDto) -> Int? {
        if let sID = episode.seasonID, let idx = seasons.firstIndex(where: { $0.id == sID }) {
            return idx
        }
        let epSeasonNum = seasonNumber(for: episode)
        if let idx = seasons.firstIndex(where: { ($0.indexNumber ?? $0.parentIndexNumber) == epSeasonNum }) {
            return idx
        }
        if let sName = episode.seasonName, let idx = seasons.firstIndex(where: { $0.name == sName }) {
            return idx
        }
        return nil
    }

    func firstEpisode(forSeasonIndex index: Int) -> BaseItemDto? {
        guard seasons.indices.contains(index) else { return nil }
        let season = seasons[index]
        let targetSeasonNum = season.indexNumber ?? season.parentIndexNumber
        return episodes.first { ep in
            if let sID = season.id, let epSeasonID = ep.seasonID, sID == epSeasonID {
                return true
            }
            if let targetSeasonNum, seasonNumber(for: ep) == targetSeasonNum {
                return true
            }
            if let sName = season.name, let epSeasonName = ep.seasonName, !sName.isEmpty, sName == epSeasonName {
                return true
            }
            return false
        }
    }

    func nextPlayableEpisode(libraryViewModel: LibraryViewModel?, fromBeginning: Bool = false) -> BaseItemDto? {
        if displayItem?.type == .episode {
            return displayItem
        }
        if displayItem?.type == .movie {
            return displayItem
        }
        if displayItem?.type == .series {
            if !fromBeginning, let resumeEp = libraryViewModel?.resumeShows.first(where: { $0.seriesID == displayItem?.id }) {
                if var matched = episodes.first(where: { $0.id == resumeEp.id }) {
                    if matched.resumePlaybackTicks == 0 && resumeEp.resumePlaybackTicks > 0 {
                        matched.userData = resumeEp.userData
                    }
                    return matched
                }
                return resumeEp
            }
            if var playable = episodes.nextPlayableItem(fromBeginning: fromBeginning) {
                if !fromBeginning, playable.resumePlaybackTicks == 0,
                   let matchingResume = libraryViewModel?.resumeShows.first(where: { $0.id == playable.id }),
                   matchingResume.resumePlaybackTicks > 0 {
                    playable.userData = matchingResume.userData
                }
                return playable
            }
            return nil
        }
        if displayItem?.type == .boxSet {
            let resolvedCollectionItems: [BaseItemDto] = collectionItems.map { ci in
                guard let id = ci.id else { return ci }
                return libraryViewModel?.item(for: id) ?? ci
            }
            guard let nextItem = resolvedCollectionItems.nextPlayableItem(fromBeginning: fromBeginning) else {
                return nil
            }
            if nextItem.type == .series {
                if !fromBeginning, let resumeEp = libraryViewModel?.resumeShows.first(where: { $0.seriesID == nextItem.id }) {
                    return resumeEp
                }
                let matching = (libraryViewModel?.episodes(forSeriesID: nextItem.id ?? "") ?? [])
                    .sorted { a, b in
                        let sA = a.parentIndexNumber ?? 1
                        let sB = b.parentIndexNumber ?? 1
                        if sA != sB { return sA < sB }
                        return (a.indexNumber ?? 1) < (b.indexNumber ?? 1)
                    }
                return matching.nextPlayableItem(fromBeginning: fromBeginning) ?? nextItem
            }
            return nextItem
        }
        return displayItem
    }

    func loadCollectionItems(client: JellyfinClient, userID: String?, libraryViewModel: LibraryViewModel? = nil) async {
        guard let collectionID = sourceItem?.id ?? detailedItem?.id else { return }
        isLoadingCollectionItems = true
        defer { isLoadingCollectionItems = false }

        let sorted = await Task.detached(priority: .userInitiated) { () -> [BaseItemDto] in
            let items = await client.fetchItemsOrEmpty(
                parameters: .collectionItems(collectionID: collectionID, userID: userID)
            )

            return items.sorted { a, b in
                let dateA = a.premiereDate ?? (a.productionYear.flatMap { Calendar.current.date(from: DateComponents(year: $0)) } ?? .distantPast)
                let dateB = b.premiereDate ?? (b.productionYear.flatMap { Calendar.current.date(from: DateComponents(year: $0)) } ?? .distantPast)
                if dateA != dateB {
                    return dateA < dateB
                }
                return (a.sortName ?? a.name ?? "") < (b.sortName ?? b.name ?? "")
            }
        }.value

        guard !Task.isCancelled else { return }

        collectionItems = sorted.map { item in
            guard let id = item.id else { return item }
            return libraryViewModel?.item(for: id) ?? item
        }
        if let collectionID = sourceItem?.id ?? detailedItem?.id {
            Self.collectionItemsCache[collectionID] = collectionItems
        }
    }
}
