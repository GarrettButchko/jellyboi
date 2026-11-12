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
    
    private var showPlaceholder: Bool {
        detailVM.specialFeatures.isLoading && (displayItem.specialFeatureCount ?? 0) > 0
    }

    @ViewBuilder
    var specialFeaturesSection: some View {
        if !detailVM.isSpecialFeaturesHidden {
            Group {
                if showPlaceholder {
                    SectionRow(
                        title: "Special Features",
                        items: .placeholders(count: 4),
                        imageAspectRatio: 9.0 / 6.0,
                        cardHeight: specialFeatureCardHeight
                    )
                    .skeleton()
                    .id("placeholder")
                    .transition(.opacity)
                } else if case .full(let features) = detailVM.specialFeatures {
                    SectionRow(title: "Special Features") {
                        ScrollView(.horizontal) {
                            LazyHStack(alignment: .top, spacing: 14) {
                                ForEach(features, id: \.id) { feature in
                                    if let featureID = feature.id {
                                        let ratio = feature.imageAspectRatio
                                        let cardWidth = specialFeatureCardHeight * ratio
                                        let zoomID = feature.zoomTransitionID(rowKey: "specialFeature")

                                        VStack(alignment: .leading, spacing: 6) {
                                            MediaCard(
                                                item: feature,
                                                posterURL: feature.backdropURL(client: serverViewModel.client)
                                                    ?? feature.thumbnailURL(client: serverViewModel.client),
                                                namespace: specialFeatureTransition,
                                                onSelect: {
                                                    specialFeatureZoomID = zoomID
                                                    selectedSpecialFeature = feature
                                                },
                                                zoomID: zoomID,
                                                imageAspectRatio: ratio,
                                                onContinueWatching: {
                                                    playbackManager.play(item: feature, fromBeginning: false, queue: features)
                                                },
                                                onStartFromBeginning: {
                                                    playbackManager.play(item: feature, fromBeginning: true, queue: features)
                                                }
                                            )
                                            .equatable()
                                            .frame(width: cardWidth, height: specialFeatureCardHeight)

                                            Text(feature.name ?? "")
                                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                                .foregroundStyle(Color.mainOpp)
                                                .lineLimit(2)
                                                .frame(width: cardWidth, alignment: .leading)
                                        }
                                        .frame(width: cardWidth)
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
            .animation(.easeInOut(duration: 0.35), value: detailVM.specialFeatures)
        }
    }
}
