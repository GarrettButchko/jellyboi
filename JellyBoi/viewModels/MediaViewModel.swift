//
//  MediaViewModel.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 8/23/26.
//

import Foundation
import Observation
import Get
import JellyfinAPI

enum MediaFilter: CaseIterable, Hashable {
    case movies
    case tvShows

    var title: String {
        switch self {
        case .movies: "Movies"
        case .tvShows: "TV Shows"
        }
    }

    var itemType: BaseItemKind {
        switch self {
        case .movies: .movie
        case .tvShows: .series
        }
    }
}

@Observable
@MainActor
class MediaViewModel {
    var filter: MediaFilter = .movies
    var movies: [BaseItemDto] = []
    var tvShows: [BaseItemDto] = []
    var isLoading = false
    var errorMessage: String?

    var currentItems: [BaseItemDto] {
        filter == .movies ? movies : tvShows
    }

    func load(using client: JellyfinClient) async {
        guard movies.isEmpty && tvShows.isEmpty else { return }
        await fetchAll(using: client)
    }

    func refresh(using client: JellyfinClient) async {
        await fetchAll(using: client)
    }

    func posterURL(for item: BaseItemDto, client: JellyfinClient) -> URL? {
        guard let id = item.id else { return nil }
        return client.url(with: Paths.getItemImage(
            itemID: id,
            imageType: "Primary",
            parameters: .init(maxWidth: 300, quality: 85)
        ))
    }

    private func fetchAll(using client: JellyfinClient) async {
        isLoading = true
        defer { isLoading = false }

        async let moviesResult = fetch(.movie, using: client)
        async let showsResult = fetch(.series, using: client)

        do {
            let (m, s) = try await (moviesResult, showsResult)
            movies = m
            tvShows = s
            errorMessage = nil
        } catch is CancellationError {
            // Refresh was interrupted; keep whatever is already loaded
        } catch {
            // Keep existing items so a failed refresh doesn't blank the grid
            errorMessage = error.localizedDescription
        }
    }

    private func fetch(_ type: BaseItemKind, using client: JellyfinClient) async throws -> [BaseItemDto] {
        let params = Paths.GetItemsParameters(
            isRecursive: true,
            sortOrder: [.ascending],
            includeItemTypes: [type],
            sortBy: [.sortName]
        )
        return try await client.send(Paths.getItems(parameters: params)).value.items ?? []
    }
}
