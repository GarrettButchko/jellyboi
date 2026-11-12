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
        detailVM.similarItems.isLoading
    }

    @ViewBuilder
    var similarItemsSection: some View {
        if !detailVM.areSimilarItemsHidden {
            Group {
                if showSimilarPlaceholder {
                    SectionRow(
                        title: "More Like This",
                        items: .placeholders(count: 4)
                    )
                    .skeleton()
                    .transition(.opacity)
                } else if case .full(let items) = detailVM.similarItems {
                    SectionRow(
                        title: "More Like This",
                        items: items,
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
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.35), value: detailVM.similarItems)
        }
    }
}
