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

    @ViewBuilder
    var similarItemsSection: some View {
        if !detailVM.areSimilarItemsHidden {
            Group {
                switch detailVM.similarItems {
                case .loading:
                    SectionRow(
                        title: "More Like This",
                        items: .placeholders
                    )
                    .skeleton()
                    .transition(.opacity)
                case .full(let items):
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
                case .empty:
                    EmptyView()
                }
            }
            .animation(.easeInOut(duration: 0.35), value: detailVM.similarItems)
        }
    }
}
