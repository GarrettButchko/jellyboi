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
                switch detailVM.collectionItems {
                case .loading:
                    MediaGrid(items: .placeholders, namespace: collectionTransition)
                        .skeleton()
                        .transition(.opacity)
                case .empty:
                    EmptyStateView(
                        icon: "film.stack",
                        title: "No Media Found",
                        message: "No movies or TV shows found in this collection."
                    )
                    .padding(.top, 20)
                    .transition(.opacity)
                case .full(let items):
                    LazyVGrid(columns: collectionColumns, spacing: 16) {
                        ForEach(items, id: \.id) { item in
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
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.35), value: detailVM.collectionItems)
        }
    }
}
