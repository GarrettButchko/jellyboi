//
//  MediaDetailViewModel.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 8/31/26.
//

import Foundation
import Observation
import Get
import JellyfinAPI

/// Loads the full `BaseItemDto` (with people, studios, ratings, tags) and
/// similar items for the given media item on appear. `MediaDetailView` renders
/// immediately from the data-poor library item and upgrades when this finishes.
@Observable
@MainActor
class MediaDetailViewModel {

    private(set) var detailedItem: BaseItemDto?
    private(set) var similarItems: [BaseItemDto] = []
    private(set) var heroReady: Bool = false
    var isLoading = false

    private var client: JellyfinClient?
    private var sourceItem: BaseItemDto?

    private var displayItem: BaseItemDto? { detailedItem ?? sourceItem }

    var backdropURL: URL? {
        guard let client, let id = displayItem?.id else { return nil }
        let hasBackdrop = !(displayItem?.backdropImageTags ?? []).isEmpty
        if hasBackdrop {
            return client.url(with: Paths.getItemImageByIndex(
                itemID: id,
                imageType: "Backdrop",
                imageIndex: 0,
                parameters: .init(maxWidth: 800, quality: 90)
            ))
        }
        return client.url(with: Paths.getItemImage(
            itemID: id,
            imageType: "Primary",
            parameters: .init(maxWidth: 800, quality: 90)
        ))
    }

    var posterURL: URL? {
        guard let client, let id = displayItem?.id else { return nil }
        return client.url(with: Paths.getItemImage(
            itemID: id,
            imageType: "Primary",
            parameters: .init(maxWidth: 600, quality: 90)
        ))
    }

    func markHeroReady() {
        heroReady = true
    }

    var logoURL: URL? {
        guard let client,
              let item = displayItem,
              let id = item.id,
              item.imageTags?["Logo"] != nil else { return nil }
        return client.url(with: Paths.getItemImage(
            itemID: id,
            imageType: "Logo",
            parameters: .init(maxWidth: 400, quality: 90)
        ))
    }

    func load(item: BaseItemDto, client: JellyfinClient, userID: String?, libraryViewModel: LibraryViewModel) async {
        guard let itemID = item.id else { return }
        self.client = client
        self.sourceItem = item
        isLoading = true
        defer { isLoading = false }

        async let detailResult: BaseItemDto? = {
            try? await client.send(Paths.getItem(itemID: itemID, userID: userID)).value
        }()
        async let similarResult: [BaseItemDto] = libraryViewModel.similarItems(
            for: itemID, client: client, userID: userID
        )

        detailedItem = await detailResult
        similarItems = await similarResult
    }

}
