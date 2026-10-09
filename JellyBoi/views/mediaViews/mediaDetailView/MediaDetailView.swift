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

private enum DownloadAlertAction {
    case cancel
    case delete
}

struct MediaDetailView: View {
    let item: BaseItemDto
    var cameFromShow: Bool = false

    init(item: BaseItemDto, cameFromShow: Bool = false) {
        self.item = item
        self.cameFromShow = cameFromShow
        _detailVM = State(initialValue: MediaDetailViewModel(item: item))
    }

    @Environment(ServerViewModel.self) var serverViewModel
    @Environment(LibraryViewModel.self) var libraryViewModel
    @Environment(PlaybackManager.self) var playbackManager
    @Environment(DownloadManager.self) var downloadManager
    @Environment(\.verticalSizeClass) var verticalSizeClass
    @Environment(\.horizontalSizeClass) var horizontalSizeClass

    @State var detailVM = MediaDetailViewModel()
    @State var showOptionsSheet = false
    @State var optionsSheetHeight: CGFloat = 0
    @State private var showDownloadsSheet: Bool = false
    @State private var downloadAlertAction: DownloadAlertAction?
    @State var selectedRelatedItem: BaseItemDto?
    @Namespace var relatedTransition
    @State var relatedZoomID: AnyHashable?
    @State var selectedCollectionItem: BaseItemDto?
    @Namespace var collectionTransition
    @State var scrollOffset: CGFloat = 0
    @State var backButtonHeight: CGFloat = 0
    @State var selectedEpisode: BaseItemDto?
    @Namespace var episodeTransition
    @State var episodeZoomID: AnyHashable?
    @State var scrolledEpisodeID: String?
    @State var hasInitialEpisodeScrolled: Bool = false
    @State var selectedPerson: BaseItemPerson?
    @State var selectedSeries: BaseItemDto?

    var displayItem: BaseItemDto { detailVM.detailedItem ?? item }

    var playableItem: BaseItemDto {
        if displayItem.type == .series || displayItem.type == .boxSet {
            return detailVM.nextPlayableEpisode(libraryViewModel: libraryViewModel) ?? displayItem
        }
        return displayItem
    }

    private var shouldShowOptionsButton: Bool {
        if displayItem.type == .series || displayItem.type == .boxSet {
            return detailVM.nextPlayableEpisode(libraryViewModel: libraryViewModel) != nil
        }
        return true
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

    // MARK: - Show Download Aggregation

    private var isShowFullyDownloaded: Bool {
        guard displayItem.type == .series else { return false }
        let showID = displayItem.id ?? item.id
        guard let showID else { return false }

        if !detailVM.episodes.isEmpty {
            return detailVM.episodes.allSatisfy { ep in
                guard let epID = ep.id else { return false }
                return downloadManager.isDownloaded(id: epID)
            }
        }

        let total = displayItem.recursiveItemCount ?? item.recursiveItemCount ?? (libraryViewModel.tvShows.first(where: { $0.id == showID })?.recursiveItemCount)
        if let total, total > 0 {
            let downloadedCount = downloadManager.completedDownloads.filter {
                $0.item.seriesID == showID || $0.item.parentBackdropItemID == showID
            }.count
            return downloadedCount >= total
        }

        return false
    }

    private var isShowDownloading: Bool {
        guard displayItem.type == .series else { return false }
        let showID = displayItem.id ?? item.id
        guard let showID else { return false }

        if !detailVM.episodes.isEmpty {
            return detailVM.episodes.contains { ep in
                guard let epID = ep.id else { return false }
                return downloadManager.isDownloading(id: epID)
            }
        }

        return downloadManager.activeDownloads.contains {
            $0.item.seriesID == showID || $0.item.parentBackdropItemID == showID
        }
    }

    private var showEpisodesLeft: Int {
        guard displayItem.type == .series else { return 0 }
        let showID = displayItem.id ?? item.id
        guard let showID else { return 0 }

        return downloadManager.activeDownloads.filter {
            $0.item.seriesID == showID ||
            $0.item.parentBackdropItemID == showID ||
            ($0.item.type == .episode && $0.item.seriesName == (displayItem.name ?? item.name))
        }.count
    }

    private var showDownloadProgress: Double {
        guard displayItem.type == .series else { return 0 }
        let showID = displayItem.id ?? item.id
        guard let showID else { return 0 }

        let downloading = downloadManager.activeDownloads.filter {
            $0.item.seriesID == showID || $0.item.parentBackdropItemID == showID
        }
        guard !downloading.isEmpty else { return 0 }

        let totalProgress = downloading.reduce(0.0) { $0 + $1.progress }
        return totalProgress / Double(downloading.count)
    }

    private var isDetailDownloaded: Bool {
        if displayItem.type == .series {
            return isShowFullyDownloaded
        }
        return downloadManager.isDownloaded(id: playableItem.id ?? "")
    }

    private var isDetailDownloading: Bool {
        if displayItem.type == .series {
            return isShowDownloading
        }
        return downloadManager.isDownloading(id: playableItem.id ?? "")
    }

    private var detailDownloadProgress: Double {
        if displayItem.type == .series {
            return showDownloadProgress
        }
        return downloadManager.progress(for: playableItem.id ?? "") ?? 0.0
    }

    func playMedia(fromBeginning: Bool) {
        let itemToPlay = (displayItem.type == .series || displayItem.type == .boxSet)
            ? (detailVM.nextPlayableEpisode(libraryViewModel: libraryViewModel, fromBeginning: fromBeginning) ?? displayItem)
            : displayItem

        playbackManager.play(
            item: itemToPlay,
            fromBeginning: fromBeginning,
            client: serverViewModel.client,
            userID: serverViewModel.currentUser?.id,
            libraryViewModel: libraryViewModel,
            mediaSourceID: detailVM.selectedMediaSourceID,
            audioStreamIndex: detailVM.selectedAudioStreamIndex,
            subtitleStreamIndex: detailVM.selectedSubtitleStreamIndex,
            maxBitrate: detailVM.selectedMaxBitrate
        )
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
                                blurRadius: 40,
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
                                .background(Color.mainOpp.opacity(0.08), in: Capsule())
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
                        if !detailVM.isOverviewHidden, let overview = displayItem.overview, !overview.isEmpty {
                            overviewSection(overview)
                                .padding(.horizontal, 20)
                        }

                        infoChipsScrollView

                        episodesSection

                        let actors = (displayItem.people ?? []).filter { $0.type == .actor }
                        if !detailVM.isCastHidden && !actors.isEmpty {
                            castSection(actors)
                        }

                        if displayItem.type == .boxSet {
                            collectionSection
                        }

                        if !detailVM.areSimilarItemsHidden && !detailVM.similarItems.isEmpty {
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

                        if !detailVM.areTagsHidden, let tags = displayItem.tags, !tags.isEmpty {
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
        .contentMargins(.top, backButtonHeight + 8, for: .scrollContent)
        .scrollEdgeEffectHidden(scrollOffset <= 0, for: .top)
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top
        } action: { _, newValue in
            scrollOffset = newValue
        }
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
                                Image(systemName: "tv")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(Color.mainOpp)
                            }
                    }
                    .glassEffect(.regular.interactive(), in: Circle())
                    .accessibilityLabel("Go to Show")
                }
                Spacer()
                MediaDetailButtonRowTopTrailing(
                    isFavorited: detailVM.isFavorite(fallback: item),
                    isDownloaded: isDetailDownloaded,
                    isDownloading: isDetailDownloading,
                    downloadProgress: detailDownloadProgress,
                    episodesLeft: displayItem.type == .series ? showEpisodesLeft : nil,
                    onOpenSheet: {
                        showDownloadsSheet = true
                    }
                ) {
                    Task {
                        await detailVM.toggleFavorite(serverViewModel: serverViewModel, fallbackItem: item)
                    }
                } onDownload: {
                    if displayItem.type == .series {
                        if isShowFullyDownloaded {
                            downloadAlertAction = .delete
                        } else if isShowDownloading {
                            downloadAlertAction = .cancel
                        } else if let client = serverViewModel.client {
                            Task {
                                for ep in detailVM.episodes {
                                    if let epID = ep.id, !downloadManager.isDownloaded(id: epID), !downloadManager.isDownloading(id: epID) {
                                        downloadManager.startDownload(item: ep, client: client)
                                    }
                                }
                            }
                        }
                    } else if let itemID = playableItem.id {
                        if downloadManager.isDownloaded(id: itemID) {
                            downloadAlertAction = .delete
                        } else if downloadManager.isDownloading(id: itemID) {
                            downloadAlertAction = .cancel
                        } else if let client = serverViewModel.client {
                            downloadManager.startDownload(item: playableItem, client: client)
                        }
                    }
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
                .presentationDetents(optionsSheetHeight > 0 ? [.height(optionsSheetHeight)] : [.medium])
                .presentationDragIndicator(.visible)
                .presentationSizing(.fitted)
        }
        .sheet(isPresented: $showDownloadsSheet) {
            if let showID = displayItem.id ?? item.id {
                ShowDownloadsSheet(seriesID: showID, seriesName: displayItem.name ?? item.name ?? "Show")
            }
        }
        .alert(
            downloadAlertAction == .cancel ? "Cancel Download?" : "Remove Download?",
            isPresented: Binding(
                get: { downloadAlertAction != nil },
                set: { if !$0 { downloadAlertAction = nil } }
            )
        ) {
            if downloadAlertAction == .cancel {
                Button("Cancel Download", role: .destructive) {
                    withAnimation(.smooth(duration: 0.25)) {
                        if displayItem.type == .series {
                            let showID = displayItem.id ?? item.id
                            for active in downloadManager.activeDownloads where (active.item.seriesID == showID || active.item.parentBackdropItemID == showID) {
                                downloadManager.cancelDownload(id: active.id)
                            }
                        } else if let itemID = playableItem.id {
                            downloadManager.cancelDownload(id: itemID)
                        }
                    }
                }
                Button("Keep Downloading", role: .cancel) { }
            } else {
                Button("Remove", role: .destructive) {
                    withAnimation(.smooth(duration: 0.25)) {
                        if displayItem.type == .series {
                            let showID = displayItem.id ?? item.id
                            for completed in downloadManager.completedDownloads where (completed.item.seriesID == showID || completed.item.parentBackdropItemID == showID) {
                                downloadManager.deleteDownload(id: completed.id)
                            }
                        } else if let itemID = playableItem.id {
                            downloadManager.deleteDownload(id: itemID)
                        }
                    }
                }
                Button("Cancel", role: .cancel) { }
            }
        } message: {
            let itemName = (displayItem.type == .series ? displayItem.name : playableItem.name) ?? "this item"
            if downloadAlertAction == .cancel {
                Text("Are you sure you want to stop downloading '\(itemName)'?")
            } else {
                Text("Are you sure you want to remove '\(itemName)' from your downloads?")
            }
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
        .task(id: item.id) {
            hasInitialEpisodeScrolled = false
            scrolledEpisodeID = nil
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
        .environment(LibraryViewModel())
        .environment(PlaybackManager())
        .environment(DownloadManager.shared)
}
