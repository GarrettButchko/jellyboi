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

    /// The synopsis is only masked while there is nothing to show yet: an item that already carries
    /// an overview keeps rendering it sharp while the rest of the details resolve.
    private var isOverviewPlaceholderVisible: Bool {
        (displayItem.overview ?? "").isEmpty && detailVM.primaryDetailsStatus.isLoading
    }

    @ViewBuilder
    var overviewSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                episodeHeaderSection
                if !detailVM.isOverviewHidden {
                    if let overview = displayItem.overview, !overview.isEmpty {
                        ExpandableText(overview)
                            .padding(.horizontal, 20)
                    } else if detailVM.primaryDetailsStatus.isLoading {
                        ExpandableText(defaultOverview)
                            .padding(.horizontal, 20)
                    }
                }
            }
            .skeleton(when: isOverviewPlaceholderVisible, value: detailVM.primaryDetailsStatus)

            infoChipsScrollView
        }
    }
}
