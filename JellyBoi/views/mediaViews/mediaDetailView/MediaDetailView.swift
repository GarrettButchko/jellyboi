//
//  MediaDetailView.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 8/23/26.
//

import SwiftUI
import UIKit
import BaseColors
import SDWebImageSwiftUI
import JellyfinAPI

private var safeAreaTop: CGFloat {
    UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .first?.keyWindow?.safeAreaInsets.top ?? 0
}

struct MediaDetailView: View {
    let item: BaseItemDto
    var cameFromShow: Bool = false

    @Environment(ServerViewModel.self) var serverViewModel
    @Environment(LibraryViewModel.self) var libraryViewModel
    @Environment(PlaybackManager.self) var playbackManager
    @Environment(\.verticalSizeClass) var verticalSizeClass
    @Environment(\.horizontalSizeClass) var horizontalSizeClass

    @State var detailVM = MediaDetailViewModel()
    @State var showOptionsSheet = false
    @State var selectedRelatedItem: BaseItemDto?
    @Namespace var relatedTransition
    @State var relatedZoomID: AnyHashable?
    @State var selectedCollectionItem: BaseItemDto?
    @Namespace var collectionTransition
    @State var backButtonHeight: CGFloat = 0
    @State var isFavorited = false
    @State var isDownloaded = false
    @Namespace var actionNamespace
    @State var selectedEpisode: BaseItemDto?
    @Namespace var episodeTransition
    @State var episodeZoomID: AnyHashable?
    @State var selectedPerson: BaseItemPerson?
    @State var selectedSeries: BaseItemDto?

    var displayItem: BaseItemDto { detailVM.detailedItem ?? item }

    private var shouldShowOptionsButton: Bool {
        let type = displayItem.type ?? item.type
        return type != .series && type != .boxSet
    }

    private var shouldShowSeriesButton: Bool {
        let type = displayItem.type ?? item.type
        guard !cameFromShow && type == .episode else { return false }
        return (displayItem.seriesID ?? item.seriesID) != nil
    }

    private var parentSeries: BaseItemDto? {
        if let series = detailVM.seriesItem {
            return series
        }
        guard let seriesID = displayItem.seriesID ?? item.seriesID else { return nil }
        if let found = libraryViewModel.tvShows.first(where: { $0.id == seriesID }) {
            return found
        }
        return BaseItemDto(
            id: seriesID,
            name: displayItem.seriesName ?? item.seriesName,
            type: .series
        )
    }

    private func navigateToOverallShow() {
        guard let series = parentSeries else { return }
        selectedSeries = series
    }

    private func playMedia(fromBeginning: Bool) {
        if let itemToPlay = detailVM.nextPlayableEpisode(libraryViewModel: libraryViewModel) {
            playbackManager.play(
                item: itemToPlay,
                fromBeginning: fromBeginning,
                client: serverViewModel.client,
                userID: serverViewModel.currentUser?.id,
                libraryViewModel: libraryViewModel
            )
        } else {
            playbackManager.play(
                item: displayItem,
                fromBeginning: fromBeginning,
                client: serverViewModel.client,
                userID: serverViewModel.currentUser?.id,
                libraryViewModel: libraryViewModel
            )
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                HStack(alignment: .bottom, spacing: 8){
                    heroImage
                        .background(alignment: .top) {
                            HeroBackdropView(
                                url: heroPosterURL,
                                itemID: displayItem.id,
                                blurRadius: 50,
                                isFlipped: true
                            )
                            .offset(y: -400)
                            .ignoresSafeArea(edges: .top)
                        }
                    MediaButtonColumn(
                        item: displayItem,
                        onOptions: shouldShowOptionsButton ? { showOptionsSheet = true } : nil,
                        onPlay: {
                            playMedia(fromBeginning: false)
                        },
                        onContinueWatching: {
                            playMedia(fromBeginning: false)
                        },
                        onStartFromBeginning: {
                            playMedia(fromBeginning: true)
                        }
                    )
                }
                .padding(.top, safeAreaTop + backButtonHeight + 8)
                .padding(.horizontal, 16)

                if displayItem.type == .episode, let episodeName = displayItem.name, !episodeName.isEmpty {
                    HStack(alignment: .center, spacing: 8) {
                        Text(episodeName)
                            .font(.system(.title3, design: .rounded, weight: .semibold))
                            .foregroundStyle(Color.mainOpp)
                        if let season = displayItem.parentIndexNumber, let episode = displayItem.indexNumber {
                            Text("S\(season) E\(episode)")
                                .font(.system(size: 9, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color.mainOpp)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .glassEffect(.regular, in: Capsule())
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                }

                SkeletonZone(showsContent: detailVM.detailedItem != nil) {
                    SkeletonDetailContent(
                        isSeries: displayItem.type == .series,
                        isCollection: displayItem.type == .boxSet
                    )
                } content: {
                    VStack(alignment: .leading, spacing: 24) {
                        if let overview = displayItem.overview, !overview.isEmpty {
                            overviewSection(overview)
                                .padding(.horizontal, 20)
                        }

                        infoChipsScrollView

                        episodesSection

                        let actors = (displayItem.people ?? []).filter { $0.type == .actor }
                        if !actors.isEmpty {
                            castSection(actors)
                        }

                        if displayItem.type == .boxSet {
                            collectionSection
                        }

                        if !detailVM.similarItems.isEmpty {
                            SectionRow(
                                title: "More Like This",
                                items: detailVM.similarItems,
                                namespace: relatedTransition,
                                rowKey: "related",
                                onSelect: { relatedItem, zoomID in
                                    relatedZoomID = zoomID
                                    selectedRelatedItem = relatedItem
                                }
                            ) { relatedItem in
                                guard let client = serverViewModel.client else { return nil }
                                return libraryViewModel.posterURL(for: relatedItem, client: client)
                            }
                        }

                        if let tags = displayItem.tags, !tags.isEmpty {
                            tagsSection(tags)
                                .padding(.horizontal, 20)
                        }

                        if hasExtraInfo {
                            extraInfoSection
                                .padding(.horizontal, 20)
                        }
                    }
                    .padding(.top, displayItem.type == .episode ? 8 : 16)
                    .padding(.bottom, 48)
                }
            }
        }
        .ignoresSafeArea(edges: .top)
        .background(Color.bg.ignoresSafeArea())
        .toolbarVisibility(.hidden, for: .navigationBar)
        .overlay(alignment: .top) {
            HStack(spacing: 8) {
                BackButton()
                if shouldShowSeriesButton {
                    Button {
                        navigateToOverallShow()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                            .padding(14)
                            .hidden()
                            .overlay {
                                Image(systemName: "square.stack.3d.up.fill")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(Color.mainOpp)
                            }
                    }
                    .glassEffect(.regular.interactive(), in: Circle())
                    .accessibilityLabel("Go to Show")
                }
                Spacer()
                MediaDetailButtonRowTopTrailing(isFavorited: detailVM.isFavorite(fallback: item)) {
                    Task {
                        await detailVM.toggleFavorite(serverViewModel: serverViewModel, fallbackItem: item)
                    }
                } onDownload: {
                    // TODO
                }
            }
            .padding(.horizontal, 16)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: {
                backButtonHeight = $0
            }
        }
        .sheet(isPresented: $showOptionsSheet) {
            optionsSheet
        }
        .navigationDestination(item: $selectedSeries) { series in
            MediaDetailView(item: series)
        }
        .navigationDestination(item: $selectedRelatedItem) { relatedItem in
            MediaDetailView(item: relatedItem)
                .navigationTransition(.zoom(
                    sourceID: relatedZoomID ?? AnyHashable(relatedItem),
                    in: relatedTransition
                ))
        }
        .navigationDestination(item: $selectedEpisode) { episode in
            MediaDetailView(item: episode, cameFromShow: true)
                .navigationTransition(.zoom(
                    sourceID: episodeZoomID ?? AnyHashable(episode),
                    in: episodeTransition
                ))
        }
        .navigationDestination(item: $selectedCollectionItem) { collectionItem in
            MediaDetailView(item: collectionItem)
                .navigationTransition(.zoom(
                    sourceID: collectionItem,
                    in: collectionTransition
                ))
        }
        .navigationDestination(item: $selectedPerson) { person in
            CastCrewView(person: person)
        }
        .onAppear {
            detailVM.prepare(item: item, client: serverViewModel.client)
        }
        .task {
            guard let client = serverViewModel.client, item.id != nil else { return }
            await detailVM.load(
                item: item,
                client: client,
                userID: serverViewModel.currentUser?.id,
                libraryViewModel: libraryViewModel
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .mediaProgressReset)) { notification in
            if let itemID = notification.object as? String {
                withAnimation(.smooth(duration: 0.35)) {
                    detailVM.clearProgress(for: itemID)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .mediaProgressUpdated)) { notification in
            if let itemID = notification.object as? String,
               let ticks = notification.userInfo?["positionTicks"] as? Int {
                let total = notification.userInfo?["durationTicks"] as? Int
                detailVM.handleProgressUpdated(itemID: itemID, positionTicks: ticks, totalTicks: total)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .mediaFavoriteToggled)) { notification in
            if let itemID = notification.object as? String,
               let isFavorite = notification.userInfo?["isFavorite"] as? Bool {
                detailVM.handleFavoriteToggled(itemID: itemID, isFavorite: isFavorite)
            }
        }
    }
}

#Preview {
    MediaDetailView(item: BaseItemDto(name: "Sample Item"))
        .environment(ServerViewModel())
        .environment(PlaybackManager())
}
