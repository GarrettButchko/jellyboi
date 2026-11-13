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
        let showSpecialFeatures: Bool = {
            #if DEBUG
            if DebugSettings.shared.hideSpecialFeatures { return false }
            #endif
            return true
        }()
        if showSpecialFeatures, (!detailVM.specialFeatures.isEmpty || (detailVM.specialFeatures.isLoading && (displayItem.specialFeatureCount ?? 0) > 0)) {
            SectionRow(title: "Special Features") {
                switch detailVM.specialFeatures {
                case .loading:
                    specialFeaturesSkeleton
                        .transition(.opacity)
                case .full(let features):
                    specialFeaturesContent(features)
                        .transition(.opacity)
                case .empty:
                    EmptyView()
                }
            }
            .animation(.easeInOut(duration: 0.2), value: detailVM.specialFeatures.isEmpty)
        }
    }

    private var specialFeaturesSkeleton: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 14) {
                ForEach(0..<4, id: \.self) { _ in
                    let cardWidth = specialFeatureCardHeight * (16.0 / 9.0)
                    VStack(alignment: .leading, spacing: 6) {
                        SkeletonBlock(cornerRadius: 16)
                            .frame(width: cardWidth, height: specialFeatureCardHeight)

                        SkeletonBlock(cornerRadius: 4)
                            .frame(width: cardWidth * 0.7, height: 13)
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
