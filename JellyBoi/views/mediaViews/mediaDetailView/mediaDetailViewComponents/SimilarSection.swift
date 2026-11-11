//
//  SimilarSection.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 9/28/26.
//

import SwiftUI
import BaseColors
import JellyfinAPI

extension MediaDetailView {

    private var showSimilarPlaceholder: Bool {
        detailVM.similarItems.isEmpty && detailVM.isLoadingSimilarItems
    }

    @ViewBuilder
    var similarItemsSection: some View {
        if !detailVM.areSimilarItemsHidden {
            Group {
                if showSimilarPlaceholder {
                    SectionRow.placeholder(
                        title: "More Like This",
                        count: 4
                    )
                    .transition(.opacity)
                } else if !detailVM.similarItems.isEmpty {
                    SectionRow(
                        title: "More Like This",
                        items: detailVM.similarItems,
                        namespace: relatedTransition,
                        rowKey: "related",
                        onSelect: { relatedItem, zoomID in
                            relatedZoomID = zoomID
                            selectedRelatedItem = relatedItem
                        }
                    ) { relatedItem in
                        guard let client = serverViewModel.client else { return nil }
                        if relatedItem.type == .episode {
                            return relatedItem.seriesPosterURL(client: client)
                                ?? relatedItem.posterURL(client: client)
                        }
                        return relatedItem.posterURL(client: client)
                    }
                }
            }
            .animation(.easeInOut(duration: 0.3), value: detailVM.isLoadingSimilarItems)
        }
    }
}
