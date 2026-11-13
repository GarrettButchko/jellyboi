//
//  MediaDetailOverviewSection.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 8/23/26.
//

import SwiftUI
import BaseColors
import JellyfinAPI

// MARK: - Skeleton Default Items

private let defaultOverview = "This is a placeholder overview text describing the plot and synopsis of the media item for skeleton loading state across multiple lines."

extension MediaDetailView {

    @ViewBuilder
    var overviewSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                episodeHeaderSection
                if !detailVM.isOverviewHidden {
                    ZStack(alignment: .topLeading) {
                        if let overview = displayItem.overview, !overview.isEmpty {
                            ExpandableText(overview)
                                .padding(.horizontal, 20)
                                .transition(.skeleton)
                        } else if detailVM.primaryDetailsStatus.isLoading {
                            ExpandableText(defaultOverview)
                                .padding(.horizontal, 20)
                                .skeleton()
                                .transition(.skeleton)
                        }
                    }
                }
            }
            infoChipsScrollView
        }
        .animation(.skeleton, value: detailVM.primaryDetailsStatus)
        .animation(.skeleton, value: displayItem.overview)
    }
}
