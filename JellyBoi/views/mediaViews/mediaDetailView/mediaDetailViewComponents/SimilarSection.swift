//
//  SimilarSection.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 9/28/26.
//

import SwiftUI
import BaseColors
import JellyfinAPI

// MARK: - Skeleton Default Items

private let defaultSimilarItem = BaseItemDto(
    id: "default-similar-item",
    name: "Media Title",
    type: .movie
)

private let defaultSimilarItems: [BaseItemDto] = (0..<8).map { index in
    BaseItemDto(
        id: "default-similar-\(index)",
        name: defaultSimilarItem.name,
        type: defaultSimilarItem.type
    )
}

extension MediaDetailView {

    @ViewBuilder
    var similarItemsSection: some View {
        if !detailVM.areSimilarItemsHidden, detailVM.secondaryStatus.isLoading || !detailVM.similarItems.isEmpty {
            SectionRow(title: "More Like This") {
                if detailVM.secondaryStatus.isLoading {
                    SectionRowMediaList(
                        items: defaultSimilarItems
                    )
                } else {
                    SectionRowMediaList(
                        items: detailVM.similarItems,
                        namespace: relatedTransition,
                        rowKey: "related",
                        onSelect: { relatedItem, zoomID in
                            relatedZoomID = zoomID
                            selectedRelatedItem = relatedItem
                        },
                        posterURL: { relatedItem in
                            guard let client = serverViewModel.client else { return nil }
                            if relatedItem.type == .episode {
                                return relatedItem.seriesPosterURL(client: client)
                                    ?? relatedItem.posterURL(client: client)
                            }
                            return relatedItem.posterURL(client: client)
                        }
                    )
                }
            }
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .move(edge: .top)),
                removal: .opacity
            ))
            .skeleton(when: detailVM.secondaryStatus.isLoading, value: detailVM.secondaryStatus)
        }
    }
}
