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

    /// Whether the synopsis text is actually rendered for the current state.
    private var isOverviewTextVisible: Bool {
        guard !detailVM.isOverviewHidden else { return false }
        if let overview = displayItem.overview, !overview.isEmpty { return true }
        return detailVM.primaryDetailsStatus.isLoading
    }

    /// Whether the episode title row above the synopsis is rendered.
    private var isEpisodeHeaderVisible: Bool {
        displayItem.type == .episode && !(displayItem.name ?? "").isEmpty
    }

    /// The synopsis with its inset, so the horizontal padding only exists alongside the text.
    @ViewBuilder
    private var overviewText: some View {
        if let overview = displayItem.overview, !overview.isEmpty {
            ExpandableText(overview)
                .padding(.horizontal, 20)
        } else if detailVM.primaryDetailsStatus.isLoading {
            ExpandableText(defaultOverview)
                .padding(.horizontal, 20)
        }
    }

    @ViewBuilder
    var overviewSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Omit the header/synopsis block entirely so its inset and stack spacing
            // collapse when there is nothing to show.
            if isEpisodeHeaderVisible || isOverviewTextVisible {
                VStack(alignment: .leading, spacing: 6) {
                    episodeHeaderSection
                    if isOverviewTextVisible {
                        overviewText
                    }
                }
                .skeleton(when: isOverviewPlaceholderVisible, value: detailVM.primaryDetailsStatus)
            }

            infoChipsScrollView
        }
    }
}
