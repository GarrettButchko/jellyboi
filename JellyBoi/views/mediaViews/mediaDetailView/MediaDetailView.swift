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
    @State var showDownloadsSheet: Bool = false
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
    @State var selectedPerson: BaseItemPerson?
    @State var selectedSeries: BaseItemDto?
    @Namespace var glassNamespace
    @Namespace var trailingButtonsNamespace

    var displayItem: BaseItemDto {
        detailVM.displayItem ?? item
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                heroSection
                episodeHeaderSection

                SkeletonZone(showsContent: detailVM.detailedItem != nil) {
                    SkeletonDetailContent(
                        isSeries: displayItem.type == .series,
                        isCollection: displayItem.type == .boxSet
                    )
                } content: {
                    VStack(alignment: .leading, spacing: 24) {
                        overviewSection
                        infoChipsScrollView
                        episodesSection
                        castSection
                        collectionSection
                        similarItemsSection
                        tagsSection
                        extraInfoSection
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
            topNavigationBar
        }
        .sheet(isPresented: $showOptionsSheet) {
            optionsSheet
                .presentationDetents(optionsSheetHeight > 0 ? [.height(optionsSheetHeight)] : [.medium])
                .presentationDragIndicator(.visible)
                .presentationSizing(.fitted)
        }
        .sheet(isPresented: $showDownloadsSheet) {
            if let showID = displayItem.id {
                ShowDownloadsSheet(seriesID: showID, seriesName: displayItem.name ?? "Show")
                    .presentationBackground(Color.bg)
            }
        }
        .alert(
            detailVM.downloadAlertAction == .cancel ? "Cancel Download?" : "Remove Download?",
            isPresented: Binding(
                get: { detailVM.downloadAlertAction != nil },
                set: { if !$0 { detailVM.downloadAlertAction = nil } }
            )
        ) {
            if detailVM.downloadAlertAction == .cancel {
                Button("Cancel Download", role: .destructive) {
                    withAnimation(.smooth(duration: 0.25)) {
                        detailVM.cancelDownload(downloadManager: downloadManager)
                    }
                }
                Button("Keep Downloading", role: .cancel) { }
            } else {
                Button("Remove", role: .destructive) {
                    withAnimation(.smooth(duration: 0.25)) {
                        detailVM.deleteDownload(downloadManager: downloadManager)
                    }
                }
                Button("Cancel", role: .cancel) { }
            }
        } message: {
            let itemName = detailVM.downloadAlertItemName(libraryViewModel: libraryViewModel)
            if detailVM.downloadAlertAction == .cancel {
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
