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

    @ViewBuilder
    var collectionSection: some View {
        if displayItem.type == .boxSet {
            SectionRow(title: "Movies & Shows") {
                ZStack(alignment: .topLeading) {
                    if detailVM.collectionStatus.isLoading {
                        MediaGrid(items: defaultCollectionItems, namespace: collectionTransition)
                            .skeleton()
                            .transition(.skeleton)
                    } else if !detailVM.collectionItems.isEmpty {
                        LazyVGrid(columns: collectionColumns, spacing: 16) {
                            ForEach(detailVM.collectionItems, id: \.id) { item in
                                MediaCard(
                                    item: item,
                                    posterURL: item.posterURL(client: serverViewModel.client),
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
                        .transition(.skeleton)
                    } else {
                        EmptyStateView(
                            icon: "film.stack",
                            title: "No Media Found",
                            message: "No movies or TV shows found in this collection."
                        )
                        .padding(.top, 20)
                        .transition(.skeleton)
                    }
                }
            }
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .move(edge: .top)),
                removal: .opacity
            ))
            .animation(.skeleton, value: detailVM.collectionStatus)
        }
    }
}
