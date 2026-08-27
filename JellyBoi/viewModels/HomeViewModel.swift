//
//  HomeViewModel.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 8/24/26.
//

import Foundation
import Observation
import Get
import JellyfinAPI
import SDWebImage
internal import Combine

@Observable
@MainActor
class HomeViewModel: ObservableObject {
    var movies: [BaseItemDto] = []
    var recommended: [BaseItemDto] = []
    var recentlyAdded: [BaseItemDto] = []
    private(set) var inProgressMovies: [BaseItemDto] = []
    private(set) var quality480p: [BaseItemDto] = []
    private(set) var quality1080p: [BaseItemDto] = []
    var isLoading = false
    var errorMessage: String?

    private func updateDerivedLists() {
        inProgressMovies = movies.filter {
            guard let percent = $0.userData?.playedPercentage else { return false }
            return percent > 0 && percent < 85
        }
        quality480p = movies.filter { item in
            guard let streams = item.mediaStreams,
                  let video = streams.first(where: { $0.type == .video }),
                  let height = video.height else { return false }
            return height < 720
        }
        quality1080p = movies.filter { item in
            guard let streams = item.mediaStreams,
                  let video = streams.first(where: { $0.type == .video }),
                  let height = video.height else { return false }
            return height >= 1080
        }
    }

    func load(using client: JellyfinClient) async {
        guard movies.isEmpty else { return }
        await refresh(using: client)
    }

    func refresh(using client: JellyfinClient) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let moviesParams = Paths.GetItemsParameters(
                isRecursive: true, sortOrder: [.ascending], fields: [.mediaStreams],
                includeItemTypes: [.movie],
                sortBy: [.sortName]
            )
            let recommendedParams = Paths.GetItemsParameters(
                limit: 20, isRecursive: true,
                sortOrder: [.descending],
                includeItemTypes: [.movie],
                sortBy: [.communityRating]
            )
            let recentParams = Paths.GetItemsParameters(
                limit: 20, isRecursive: true,
                sortOrder: [.descending],
                includeItemTypes: [.movie],
                sortBy: [.dateCreated]
            )

            async let moviesResult = client.send(Paths.getItems(parameters: moviesParams)).value.items
            async let recommendedResult = client.send(Paths.getItems(parameters: recommendedParams)).value.items
            async let recentResult = client.send(Paths.getItems(parameters: recentParams)).value.items

            movies = try await moviesResult ?? []
            recommended = try await recommendedResult ?? []
            recentlyAdded = try await recentResult ?? []
            updateDerivedLists()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func prefetchBackdrops(around index: Int, client: JellyfinClient) {
        let neighbors = [index - 1, index, index + 1]
            .filter { $0 >= 0 && $0 < movies.count }
        let urls = neighbors.compactMap { backgroundURL(for: movies[$0], client: client) }
        SDWebImagePrefetcher.shared.prefetchURLs(urls)
    }

    func prefetchPosters(around index: Int, client: JellyfinClient) {
        let neighbors = [index - 1, index, index + 1]
            .filter { $0 >= 0 && $0 < movies.count }
        let urls = neighbors.compactMap { posterURL(for: movies[$0], client: client) }
        SDWebImagePrefetcher.shared.prefetchURLs(urls)
    }

    func posterURL(for item: BaseItemDto, client: JellyfinClient) -> URL? {
        guard let id = item.id else { return nil }
        return client.url(with: Paths.getItemImage(
            itemID: id,
            imageType: "Primary",
            parameters: .init(maxWidth: 400, quality: 80)
        ))
    }

    func backgroundURL(for item: BaseItemDto, client: JellyfinClient) -> URL? {
        guard let id = item.id else { return nil }
        return client.url(with: Paths.getItemImage(
            itemID: id,
            imageType: "Backdrop",
            parameters: .init(maxWidth: 800, quality: 80)
        ))
    }

    func backdropURL(for item: BaseItemDto, client: JellyfinClient) -> URL? {
        guard let id = item.id else { return nil }
        let imageType = item.imageTags?.keys.contains("Thumb") == true ? "Thumb" : "Backdrop"
        return client.url(with: Paths.getItemImage(
            itemID: id,
            imageType: imageType,
            parameters: .init(maxWidth: 600, quality: 85)
        ))
    }
}
