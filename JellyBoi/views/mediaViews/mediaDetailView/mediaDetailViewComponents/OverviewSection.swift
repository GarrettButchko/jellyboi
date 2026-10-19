//
//  MediaDetailOverviewSection.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 8/23/26.
//

import SwiftUI
import BaseColors
import JellyfinAPI

extension MediaDetailView {

    @ViewBuilder
    var overviewSection: some View {
        if !detailVM.isOverviewHidden, let overview = displayItem.overview, !overview.isEmpty {
            ExpandableText(overview)
                .padding(.horizontal, 20)
        }
    }
}
