//
//  SpecialFeaturesSection.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 10/28/26.
//

import SwiftUI
import BaseColors
import JellyfinAPI

extension MediaDetailView {

    private var specialFeatureCardHeight: CGFloat {
        horizontalSizeClass == .regular ? 140 : 110
    }

    private var specialFeatureItemHeight: CGFloat {
        specialFeatureCardHeight + 46
    }

    @ViewBuilder
    var specialFeaturesSection: some View {
        if !detailVM.isSpecialFeaturesHidden {
            Group {
                if detailVM.specialFeatures.isEmpty {
                    if detailVM.isLoadingSpecialFeatures && (displayItem.specialFeatureCount ?? 0) > 0 {
                        SectionRow.placeholder(
                            title: "Special Features",
                            count: 4,
                            imageAspectRatio: 16.0 / 9.0
                        )
                        .transition(.opacity)
                    }
                } else {
                    SectionRow(title: "Special Features") {
                        ScrollView(.horizontal) {
                            LazyHStack(alignment: .top, spacing: 14) {
                                ForEach(detailVM.specialFeatures, id: \.id) { feature in
                                    if let featureID = feature.id {
                                        let ratio = feature.imageAspectRatio
                                        let cardWidth = specialFeatureCardHeight * ratio
                                        let zoomID = feature.zoomTransitionID(rowKey: "specialFeature")

                                        VStack(alignment: .leading, spacing: 6) {
                                            MediaCard(
                                                item: feature,
                                                posterURL: feature.thumbnailURL(client: serverViewModel.client),
                                                namespace: specialFeatureTransition,
                                                onSelect: {
                                                    playbackManager.play(
                                                        item: feature,
                                                        fromBeginning: false,
                                                        client: serverViewModel.client,
                                                        userID: serverViewModel.currentUser?.id,
                                                        libraryViewModel: libraryViewModel
                                                    )
                                                },
                                                zoomID: zoomID,
                                                imageAspectRatio: ratio,
                                                onContinueWatching: {
                                                    playbackManager.play(
                                                        item: feature,
                                                        fromBeginning: false,
                                                        client: serverViewModel.client,
                                                        userID: serverViewModel.currentUser?.id,
                                                        libraryViewModel: libraryViewModel
                                                    )
                                                },
                                                onStartFromBeginning: {
                                                    playbackManager.play(
                                                        item: feature,
                                                        fromBeginning: true,
                                                        client: serverViewModel.client,
                                                        userID: serverViewModel.currentUser?.id,
                                                        libraryViewModel: libraryViewModel
                                                    )
                                                }
                                            )
                                            .frame(width: cardWidth, height: specialFeatureCardHeight)

                                            Text(feature.name ?? "Special Feature")
                                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                                .foregroundStyle(Color.mainOpp)
                                                .lineLimit(2)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                        .frame(width: cardWidth, height: specialFeatureItemHeight, alignment: .top)
                                        .id(featureID)
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .scrollTargetLayout()
                        }
                        .frame(height: specialFeatureItemHeight)
                        .scrollClipDisabled()
                        .scrollIndicators(.hidden)
                        .scrollTargetBehavior(.viewAligned)
                    }
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: detailVM.specialFeatures.isEmpty)
        }
    }
}
