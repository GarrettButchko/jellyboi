//
//  CollectionSection.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 9/2/26.
//

import SwiftUI
import BaseColors
import SDWebImageSwiftUI
import JellyfinAPI

// MARK: - Skeleton Default Items

private let defaultCollectionItem = BaseItemDto(
    id: "default-collection-item",
    name: "Movie or Show",
    type: .movie
)

private let defaultCollectionItems: [BaseItemDto] = (0..<6).map { index in
    BaseItemDto(
        id: "default-collection-\(index)",
        name: defaultCollectionItem.name,
        type: defaultCollectionItem.type
    )
}

extension MediaDetailView {

    private var collectionColumns: [GridItem] {
        [GridItem(.adaptive(minimum: horizontalSizeClass == .regular ? 160 : 110), spacing: 16)]
    }

    private var shouldIncludeCollection: Bool {
        displayItem.type == .boxSet
    }

    @ViewBuilder
    var collectionSection: some View {
        if shouldIncludeCollection {
            SectionRow(title: "Movies & Shows") {
                if detailVM.collectionStatus.isLoading {
                    collectionSkeleton
                } else {
                    collectionContent
                }
            }
            .skeleton(when: detailVM.collectionStatus.isLoading, value: detailVM.collectionItems.count)
        }
    }

    private var collectionSkeleton: some View {
        MediaGrid(itemIDs: defaultCollectionItems.compactMap(\.id), namespace: collectionTransition)
    }

    @ViewBuilder
    private var collectionContent: some View {
        if detailVM.collectionItems.isEmpty {
            EmptyStateView(
                icon: "film.stack",
                title: "No Media Found",
                message: "No movies or TV shows found in this collection."
            )
            .padding(.top, 20)
        } else {
            LazyVGrid(columns: collectionColumns, spacing: 16) {
                ForEach(detailVM.collectionItems, id: \.self) { itemID in
                    let item = LibraryViewModel.shared[itemID]
                    MediaCard(
                        itemID: itemID,
                        posterURL: item?.posterURL(client: serverViewModel.client),
                        namespace: collectionTransition,
                        onSelect: {
                            selectedCollectionItem = item
                        }
                    )
                    .equatable()
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
    }
}
