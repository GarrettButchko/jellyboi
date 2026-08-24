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

@Observable
@MainActor
class HomeViewModel {
    var movies: [BaseItemDto] = []
    var isLoading = false
    var errorMessage: String?

    func load(using client: JellyfinClient) async {
        guard movies.isEmpty else { return }
        await refresh(using: client)
    }

    func refresh(using client: JellyfinClient) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let params = Paths.GetItemsParameters(
                isRecursive: true,
                sortOrder: [.ascending],
                includeItemTypes: [.movie],
                sortBy: [.sortName]
            )
            movies = try await client.send(Paths.getItems(parameters: params)).value.items ?? []
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func backdropURL(for item: BaseItemDto, client: JellyfinClient) -> URL? {
        guard let id = item.id else { return nil }
        // Prefer the 16:9 Thumb card; many items only have a Backdrop, so fall back to it
        let imageType = item.imageTags?.keys.contains("Thumb") == true ? "Thumb" : "Backdrop"
        return client.url(with: Paths.getItemImage(
            itemID: id,
            imageType: imageType,
            parameters: .init(maxWidth: 600, quality: 85)
        ))
    }
}
