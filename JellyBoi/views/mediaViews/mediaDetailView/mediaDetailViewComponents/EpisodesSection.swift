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
        let showEpisodes: Bool = {
            #if DEBUG
            if DebugSettings.shared.hideEpisodes { return false }
            #endif
            return true
        }()
        if showEpisodes, displayItem.type == .series, (!detailVM.seasons.isEmpty || detailVM.isLoadingEpisodes) {
            ScrollViewReader { proxy in
                SectionRow(
                    title: "Episodes",
                    headerAccessory: {
                        if detailVM.seasons.count > 1 {
                            seasonMenu(proxy: proxy)
                        }
                    }
                ) {
                    if detailVM.episodes.isEmpty {
                        if detailVM.isLoadingEpisodes {
                            ScrollView(.horizontal) {
                                HStack(alignment: .top, spacing: 12) {
                                    ForEach(0..<5, id: \.self) { _ in
                                        SkeletonBlock(cornerRadius: 16)
                                            .frame(width: episodeCardHeight * (16.0 / 9.0), height: episodeCardHeight)
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                            .scrollClipDisabled()
                            .scrollIndicators(.hidden)
                            .skeleton()
                            .transition(.opacity)
                        }
                    } else {
                        ScrollView(.horizontal) {
                            LazyHStack(alignment: .top, spacing: 12) {
                                ForEach(detailVM.episodes, id: \.id) { episode in
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
                                                playbackManager.play(item: episode, fromBeginning: false, queue: detailVM.episodes)
                                            },
                                            onStartFromBeginning: {
                                                playbackManager.play(item: episode, fromBeginning: true, queue: detailVM.episodes)
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
                        .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: detailVM.seasons.count)
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
