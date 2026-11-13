//
//  SpecialFeaturesSection.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 10/28/26.
//

import SwiftUI
import BaseColors
import JellyfinAPI

// MARK: - Skeleton Default Items

private let defaultSpecialFeature = BaseItemDto(
    id: "default-feature",
    name: "Special Feature Title",
    type: .video
)

private let defaultSpecialFeatures: [BaseItemDto] = (0..<4).map { index in
    BaseItemDto(
        id: "default-feature-\(index)",
        name: defaultSpecialFeature.name,
        type: defaultSpecialFeature.type
    )
}

extension MediaDetailView {

    private var specialFeatureCardHeight: CGFloat {
        horizontalSizeClass == .regular ? 140 : 110
    }

    private var specialFeatureItemHeight: CGFloat {
        specialFeatureCardHeight + 46
    }

    @ViewBuilder
    var specialFeaturesSection: some View {
        let showSpecialFeatures: Bool = {
            #if DEBUG
            if DebugSettings.shared.hideSpecialFeatures { return false }
            #endif
            return true
        }()
        if showSpecialFeatures, detailVM.secondaryStatus.isLoading || !detailVM.specialFeatures.isEmpty {
            SectionRow(title: "Special Features") {
                ZStack(alignment: .topLeading) {
                    if detailVM.secondaryStatus.isLoading {
                        specialFeaturesSkeleton
                            .transition(.skeleton)
                    } else {
                        specialFeaturesContent(detailVM.specialFeatures)
                            .transition(.skeleton)
                    }
                }
            }
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .move(edge: .top)),
                removal: .opacity
            ))
            .animation(.skeleton, value: detailVM.secondaryStatus)
        }
    }

    private var specialFeaturesSkeleton: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 14) {
                ForEach(defaultSpecialFeatures, id: \.id) { feature in
                    let cardWidth = specialFeatureCardHeight * (16.0 / 9.0)
                    VStack(alignment: .leading, spacing: 6) {
                        MediaCard(
                            item: feature,
                            posterURL: nil,
                            imageAspectRatio: 16.0 / 9.0
                        )
                        .frame(width: cardWidth, height: specialFeatureCardHeight)

                        Text(feature.name ?? "")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.mainOpp)
                            .lineLimit(2)
                            .frame(width: cardWidth, alignment: .leading)
                    }
                    .frame(width: cardWidth)
                }
            }
            .padding(.horizontal, 16)
        }
        .frame(height: specialFeatureItemHeight)
        .scrollClipDisabled()
        .scrollIndicators(.hidden)
        .skeleton()
    }

    private func specialFeaturesContent(_ features: [BaseItemDto]) -> some View {
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
}
