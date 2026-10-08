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
            ScrollViewReader { proxy in
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .center) {
                        Text("Episodes")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(Color.mainOpp)

                        Spacer()

                        if detailVM.seasons.count > 1 {
                            seasonMenu(proxy: proxy)
                        }
                    }
                    .padding(.horizontal, 16)

                    if detailVM.episodes.isEmpty {
                        if detailVM.isLoadingEpisodes {
                            SkeletonEpisodesRow()
                                .transition(.opacity)
                        }
                    } else {
                        ScrollView(.horizontal) {
                            LazyHStack(alignment: .top, spacing: 12) {
                                ForEach(detailVM.episodes, id: \.id) { episode in
                                    if let episodeID = episode.id {
                                        let cardWidth = episodeCardHeight * episode.imageAspectRatio
                                        let zoomID: AnyHashable = AnyHashable("episode-\(episodeID)")

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
                                        .id(episodeID)
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .scrollTargetLayout()
                        }
                        .scrollClipDisabled()
                        .scrollIndicators(.hidden)
                        .scrollTargetBehavior(.viewAligned)
                        .scrollPosition(id: $scrolledEpisodeID, anchor: .leading)
                        .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: detailVM.episodes.isEmpty)
                .task(id: detailVM.episodes.count) {
                    guard !hasInitialEpisodeScrolled, !detailVM.episodes.isEmpty else { return }
                    let nextEp = detailVM.nextPlayableEpisode(libraryViewModel: libraryViewModel)
                    if let targetID = nextEp?.id {
                        hasInitialEpisodeScrolled = true
                        scrolledEpisodeID = targetID
                        if let nextEp, let sIdx = detailVM.seasonIndex(for: nextEp) {
                            detailVM.selectedSeasonIndex = sIdx
                        }
                        try? await Task.sleep(nanoseconds: 50_000_000)
                        proxy.scrollTo(targetID, anchor: .leading)
                    }
                }
                .onChange(of: scrolledEpisodeID) { _, newEpisodeID in
                    guard hasInitialEpisodeScrolled,
                          let newEpisodeID,
                          let ep = detailVM.episodes.first(where: { $0.id == newEpisodeID }),
                          let sIdx = detailVM.seasonIndex(for: ep) else { return }
                    if detailVM.selectedSeasonIndex != sIdx {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            detailVM.selectedSeasonIndex = sIdx
                        }
                    }
                }
            }
        }
    }

    private func seasonMenu(proxy: ScrollViewProxy) -> some View {
        Menu {
            ForEach(detailVM.seasons.indices, id: \.self) { index in
                let season = detailVM.seasons[index]
                let isSelected = (index == detailVM.selectedSeasonIndex)
                Button {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        detailVM.selectedSeasonIndex = index
                        if let firstEpID = detailVM.firstEpisode(forSeasonIndex: index)?.id {
                            scrolledEpisodeID = firstEpID
                            proxy.scrollTo(firstEpID, anchor: .leading)
                        }
                    }
                } label: {
                    if isSelected {
                        Label(seasonLabel(season), systemImage: "checkmark")
                    } else {
                        Text(seasonLabel(season))
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(currentSeasonTitle)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(Color.mainOpp)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .glassEffect(.regular.interactive(), in: Capsule())
        }
    }

    private var currentSeasonTitle: String {
        if detailVM.seasons.indices.contains(detailVM.selectedSeasonIndex) {
            return seasonLabel(detailVM.seasons[detailVM.selectedSeasonIndex])
        }
        return "Season"
    }

    private func seasonLabel(_ season: BaseItemDto) -> String {
        if let name = season.name, !name.isEmpty {
            return name
        }
        if let number = season.indexNumber ?? season.parentIndexNumber {
            return "Season \(number)"
        }
        return "Season"
    }
}
