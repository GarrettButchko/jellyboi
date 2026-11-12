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
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                episodeHeaderSection
                if !detailVM.isOverviewHidden {
                    if let overview = displayItem.overview, !overview.isEmpty {
                        ExpandableText(overview)
                            .padding(.horizontal, 20)
                            .transition(.opacity)
                    } else if detailVM.isLoading {
                        VStack(alignment: .leading, spacing: 8) {
                            SkeletonBlock(cornerRadius: 4).frame(maxWidth: .infinity).frame(height: 14)
                            SkeletonBlock(cornerRadius: 4).frame(maxWidth: .infinity).frame(height: 14)
                            SkeletonBlock(cornerRadius: 4).frame(height: 14).frame(maxWidth: .infinity, alignment: .leading).padding(.trailing, 80)
                        }
                        .padding(.horizontal, 20)
                        .skeleton()
                        .transition(.opacity)
                    }
                }
            }
            infoChipsScrollView
        }
        .animation(.easeInOut(duration: 0.35), value: detailVM.isLoading)
    }
}
