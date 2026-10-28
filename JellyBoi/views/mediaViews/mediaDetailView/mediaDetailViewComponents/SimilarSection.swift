//
//  MediaDetailSimilarSection.swift
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
        if !detailVM.areSimilarItemsHidden && !detailVM.similarItems.isEmpty {
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
                    return libraryViewModel.seriesPosterURL(for: relatedItem, client: client)
                        ?? libraryViewModel.posterURL(for: relatedItem, client: client)
                }
                return libraryViewModel.posterURL(for: relatedItem, client: client)
            }
        }
    }
}
