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
            VStack(alignment: .leading, spacing: 12) {
                Text("Movies & Shows")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color.mainOpp)
                    .padding(.horizontal, 16)

                if detailVM.collectionItems.isEmpty {
                    if detailVM.isLoadingCollectionItems {
                        SkeletonMediaGrid()
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
                                posterURL: serverViewModel.client.flatMap { libraryViewModel.posterURL(for: item, client: $0) },
                                namespace: collectionTransition
                            ) {
                                selectedCollectionItem = item
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
        }
    }
}
