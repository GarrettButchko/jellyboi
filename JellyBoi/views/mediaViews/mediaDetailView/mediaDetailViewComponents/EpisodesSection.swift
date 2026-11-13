//
//  MediaDetailEpisodesSection.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 9/7/26.
//

import SwiftUI
import BaseColors
import JellyfinAPI

// MARK: - Skeleton Default Items

private let defaultEpisode = BaseItemDto(
    id: "default-episode",
    indexNumber: 1,
    name: "Episode Title",
    overview: "Episode overview text description.",
    parentIndexNumber: 1,
    type: .episode
)

private let defaultEpisodes: [BaseItemDto] = (0..<5).map { index in
    BaseItemDto(
        id: "default-episode-\(index)",
        indexNumber: index + 1,
        name: defaultEpisode.name,
        overview: defaultEpisode.overview,
        parentIndexNumber: defaultEpisode.parentIndexNumber,
        type: defaultEpisode.type
    )
}

extension MediaDetailView {

    @ViewBuilder
    var episodeHeaderSection: some View {
        if displayItem.type == .episode, let episodeName = displayItem.name, !episodeName.isEmpty {
            HStack(alignment: .center, spacing: 8) {
                Text(episodeName)
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .foregroundStyle(Color.mainOpp)
                if let epNumber = displayItem.formattedEpisodeNumber {
                    Text(epNumber)
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.mainOpp)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color.mainOpp.opacity(0.08), in: Capsule())
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private var episodeCardHeight: CGFloat {
        horizontalSizeClass == .regular ? 140 : 120
    }

    @ViewBuilder
    var episodesSection: some View {
        if !detailVM.isEpisodesHidden, displayItem.type == .series, !detailVM.episodesStatus.isEmpty {
            ScrollViewReader { proxy in
                SectionRow(
                    title: "Episodes",
                    headerAccessory: {
                        if detailVM.seasons.count > 1 {
                            seasonMenu(proxy: proxy)
                        }
                    }
                ) {
                    if detailVM.episodesStatus.isLoading {
                        episodesSkeleton
                    } else {
                        episodesContent(detailVM.episodes)
                    }
                }
                .skeleton(when: detailVM.episodesStatus.isLoading, value: detailVM.episodesStatus)
                .animation(.skeleton, value: detailVM.seasons.count)
                .task(id: detailVM.episodes.count) {
                    guard !detailVM.hasInitialEpisodeScrolled, !detailVM.episodes.isEmpty else { return }
                    let nextEp = detailVM.nextPlayableEpisode(libraryViewModel: libraryViewModel)
                    if let targetID = nextEp?.id {
                        detailVM.hasInitialEpisodeScrolled = true
                        detailVM.scrolledEpisodeID = targetID
                        if let nextEp, let sIdx = detailVM.seasonIndex(for: nextEp) {
                            detailVM.selectedSeasonIndex = sIdx
                        }
                        try? await Task.sleep(nanoseconds: 50_000_000)
                        proxy.scrollTo(targetID, anchor: .leading)
                    }
                }
                .onChange(of: detailVM.scrolledEpisodeID) { _, newEpisodeID in
                    guard detailVM.hasInitialEpisodeScrolled,
                          let newEpisodeID,
                          let ep = detailVM.episodes.first(where: { $0.id == newEpisodeID }),
                          let sIdx = detailVM.seasonIndex(for: ep) else { return }
                    if detailVM.selectedSeasonIndex != sIdx {
                        withAnimation(.skeleton) {
                            detailVM.selectedSeasonIndex = sIdx
                        }
                    }
                }
            }
        }
    }
    
    private var episodesSkeleton: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(defaultEpisodes, id: \.id) { episode in
                    let cardWidth = episodeCardHeight * MediaAspectRatio.thumbnail
                    MediaCard(
                        item: episode,
                        posterURL: nil,
                        imageAspectRatio: MediaAspectRatio.thumbnail
                    )
                    .frame(width: cardWidth, height: episodeCardHeight)
                }
            }
            .padding(.horizontal, 16)
        }
        .frame(height: episodeCardHeight)
        .scrollClipDisabled()
        .scrollIndicators(.hidden)
    }
    
    private func episodesContent(_ episodes: [BaseItemDto]) -> some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: 12) {
                ForEach(episodes, id: \.id) { episode in
                    if let episodeID = episode.id {
                        let cardWidth = episodeCardHeight * episode.imageAspectRatio
                        let zoomID = episode.zoomTransitionID(rowKey: "episode")

                        MediaCard(
                            item: episode,
                            posterURL: episode.thumbnailURL(client: serverViewModel.client),
                            namespace: episodeTransition,
                            onSelect: {
                                episodeZoomID = zoomID
                                selectedEpisode = episode
                            },
                            zoomID: zoomID,
                            imageAspectRatio: episode.imageAspectRatio,
                            onContinueWatching: {
                                playbackManager.play(item: episode, fromBeginning: false, queue: episodes)
                            },
                            onStartFromBeginning: {
                                playbackManager.play(item: episode, fromBeginning: true, queue: episodes)
                            }
                        )
                        .equatable()
                        .frame(width: cardWidth, height: episodeCardHeight)
                        .id(episodeID)
                    }
                }
            }
            .padding(.horizontal, 16)
            .scrollTargetLayout()
        }
        .frame(height: episodeCardHeight)
        .scrollClipDisabled()
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $detailVM.scrolledEpisodeID, anchor: .leading)
        
    }

    private func seasonMenu(proxy: ScrollViewProxy) -> some View {
        Menu {
            ForEach(detailVM.seasons.indices, id: \.self) { index in
                let season = detailVM.seasons[index]
                let isSelected = (index == detailVM.selectedSeasonIndex)
                Button {
                    withAnimation(.skeleton) {
                        detailVM.selectedSeasonIndex = index
                        if let firstEpID = detailVM.firstEpisode(forSeasonIndex: index)?.id {
                            detailVM.scrolledEpisodeID = firstEpID
                            proxy.scrollTo(firstEpID, anchor: .leading)
                        }
                    }
                } label: {
                    if isSelected {
                        Label {
                            Text(seasonLabel(season))
                        } icon: {
                            Image(systemName: "checkmark")
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(Color.mainOpp)
                        }
                        .foregroundStyle(Color.mainOpp)
                        .tint(Color.mainOpp)
                    } else {
                        Text(seasonLabel(season))
                    }
                }
                .tint(Color.mainOpp)
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
        .tint(Color.mainOpp)
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
