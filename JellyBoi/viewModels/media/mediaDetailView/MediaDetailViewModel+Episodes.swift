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
            episodes = []
            episodesStatus = .empty
            return
        }
        episodesStatus = .loading

        // 1. Fetch all episodes for the series concurrently across all seasons in a single request
        async let rawEpisodesTask = client.fetchEpisodesOrEmpty(seriesID: seriesID, userID: userID)

        // 2. Fetch seasons and sort them off the main actor
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

        // Publish seasons immediately if available so the season picker appears without waiting for episodes
        if !sortedSeasons.isEmpty {
            self.seasons = sortedSeasons
            if !seasons.indices.contains(selectedSeasonIndex) {
                selectedSeasonIndex = 0
            }
        }

        // 3. Await all episodes from the single series request
        let rawEpisodes = await rawEpisodesTask
        guard !Task.isCancelled else { return }

        // Fallback to deriving seasons from episodes if seasons fetch returned empty
        let resolvedSeasons = sortedSeasons.isEmpty
            ? Self.deriveSeasons(from: rawEpisodes, seriesID: seriesID)
            : sortedSeasons

        if self.seasons.isEmpty && !resolvedSeasons.isEmpty {
            self.seasons = resolvedSeasons
            if !seasons.indices.contains(selectedSeasonIndex) {
                selectedSeasonIndex = 0
            }
        }

        guard !resolvedSeasons.isEmpty, !rawEpisodes.isEmpty else {
            self.episodes = []
            self.episodesStatus = .empty
            return
        }

        // 4. Sort episodes by season number and episode number off the main actor
        var seasonNumberMap: [String: Int] = [:]
        for season in resolvedSeasons {
            if let id = season.id {
                seasonNumberMap[id] = season.indexNumber ?? season.parentIndexNumber ?? 1
            }
        }

        let sortedEpisodes = await Task.detached(priority: .userInitiated) { [rawEpisodes, seasonNumberMap] () -> [BaseItemDto] in
            rawEpisodes.sorted { a, b in
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

        for ep in sortedEpisodes {
            if let id = ep.id {
                library[id] = ep
            }
        }

        let ids = sortedEpisodes.compactMap(\.id)
        self.episodes = ids
        self.episodesStatus = ids.isEmpty ? .empty : .loaded

        if !hasInitialEpisodeScrolled {
            if let nextEpID = nextPlayableItem,
               let sIdx = seasonIndex(for: nextEpID) {
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

    func seasonIndex(for episodeID: String) -> Int? {
        if let ep = library[episodeID] {
            return seasonIndex(for: ep)
        }
        return nil
    }

    func firstEpisode(forSeasonIndex index: Int) -> BaseItemDto? {
        guard seasons.indices.contains(index) else { return nil }
        let season = seasons[index]
        let targetSeasonNum = season.indexNumber ?? season.parentIndexNumber
        let epItems = episodes.compactMap { library[$0] }
        return epItems.first { ep in
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

    func loadCollectionItems(client: JellyfinClient, userID: String?) async {
        guard let collectionID = sourceItem?.id ?? detailedItem?.id else { return }
        collectionStatus = .loading

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

        for item in sorted {
            if let id = item.id {
                library[id] = item
            }
        }
        let ids = sorted.compactMap(\.id)
        collectionItems = ids
        collectionStatus = ids.isEmpty ? .empty : .loaded
    }
}
