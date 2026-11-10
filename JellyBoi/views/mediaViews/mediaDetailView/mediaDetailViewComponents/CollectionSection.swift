//
//  MediaDetailCollectionSection.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 9/28/26.
//

import SwiftUI
import BaseColors
import JellyfinAPI

extension MediaDetailView {

    private var collectionColumns: [GridItem] {
        [GridItem(.adaptive(minimum: horizontalSizeClass == .regular ? 160 : 110), spacing: 16)]
    }

    @ViewBuilder
    var collectionSection: some View {
        if displayItem.type == .boxSet {
            SectionRow(title: "Movies & Shows") {
                if detailVM.collectionItems.isEmpty {
                    if detailVM.isLoadingCollectionItems {
                        MediaGrid.placeholder(count: 12, namespace: collectionTransition)
                    } else {
                        EmptyStateView(
                            icon: "film.stack",
                            title: "No Media Found",
                            message: "No movies or TV shows found in this collection."
                        )
                        .padding(.top, 20)
                    }
                } else {
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
                }
            }
        }
    }
}
