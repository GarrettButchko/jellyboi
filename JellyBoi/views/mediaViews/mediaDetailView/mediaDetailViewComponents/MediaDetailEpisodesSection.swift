//
//  MediaDetailEpisodesSection.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 9/7/26.
//

import SwiftUI
import BaseColors
import JellyfinAPI

extension MediaDetailView {

    private var episodeCardHeight: CGFloat {
        horizontalSizeClass == .regular ? 140 : 120
    }

    @ViewBuilder
    var episodesSection: some View {
        let showEpisodes: Bool = {
            #if DEBUG
            if DebugSettings.shared.hideEpisodes { return false }
            #endif
            return true
        }()
        if showEpisodes, displayItem.type == .series, (!detailVM.seasons.isEmpty || detailVM.isLoadingEpisodes) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Episodes")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color.mainOpp)
                    .padding(.horizontal, 16)

                if detailVM.seasons.count > 1 {
                    Picker("Season", selection: $detailVM.selectedSeasonIndex) {
                        ForEach(detailVM.seasons.indices, id: \.self) { index in
                            Text(seasonLabel(detailVM.seasons[index]))
                                .tag(index)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .onChange(of: detailVM.selectedSeasonIndex) { _, newIndex in
                        guard let client = serverViewModel.client else { return }
                        Task {
                            await detailVM.selectSeason(newIndex, client: client, userID: serverViewModel.currentUser?.id)
                        }
                    }
                }

                if detailVM.episodes.isEmpty {
                    if detailVM.isLoadingEpisodes {
                        SkeletonEpisodesRow()
                            .transition(.opacity)
                    }
                } else {
                    ScrollView(.horizontal) {
                        LazyHStack(alignment: .top, spacing: 12) {
                            ForEach(Array(detailVM.episodes.enumerated()), id: \.element.id) { index, episode in
                                let cardWidth = episodeCardHeight * episode.imageAspectRatio
                                let zoomID: AnyHashable = AnyHashable("episode-\(detailVM.selectedSeasonIndex)-\(index)")

                                MediaCard(
                                    item: episode,
                                    posterURL: detailVM.episodeThumbnailURL(for: episode),
                                    namespace: episodeTransition,
                                    onSelect: {
                                        episodeZoomID = zoomID
                                        selectedEpisode = episode
                                    },
                                    zoomID: zoomID,
                                    imageAspectRatio: episode.imageAspectRatio,
                                    onContinueWatching: {
                                        playbackManager.play(item: episode, fromBeginning: false)
                                    },
                                    onStartFromBeginning: {
                                        playbackManager.play(item: episode, fromBeginning: true)
                                    }
                                )
                                .frame(width: cardWidth, height: episodeCardHeight)
                            }
                        }
                        .padding(.horizontal, 16)
                        .scrollTargetLayout()
                    }
                    .scrollClipDisabled()
                    .scrollIndicators(.hidden)
                    .scrollTargetBehavior(.viewAligned)
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: detailVM.episodes.isEmpty)
        }
    }

    private func seasonLabel(_ season: BaseItemDto) -> String {
        if let name = season.name, !name.isEmpty {
            return name
        }
        if let number = season.parentIndexNumber {
            return "Season \(number)"
        }
        return "Season"
    }
}
