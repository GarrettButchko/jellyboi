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

    @Environment(ServerViewModel.self) var serverViewModel
    @Environment(LibraryViewModel.self) var libraryViewModel
    @Environment(\.verticalSizeClass) var verticalSizeClass
    @Environment(\.horizontalSizeClass) var horizontalSizeClass

    @State var detailVM = MediaDetailViewModel()
    @State var isOverviewExpanded = false
    @State var overviewLimitedHeight: CGFloat = 0
    @State var overviewFullHeight: CGFloat = 0
    @State var showOptionsSheet = false
    @State var selectedRelatedItem: BaseItemDto?
    @Namespace var relatedTransition
    @State var relatedZoomID: AnyHashable?
    @State var moreButtonHeight: CGFloat = 0
    @State var backButtonHeight: CGFloat = 0
    @State var isFavorited = false
    @State var isDownloaded = false
    @Namespace var actionNamespace
    @State var selectedEpisode: BaseItemDto?
    @Namespace var episodeTransition
    @State var episodeZoomID: AnyHashable?

    var isDescriptionTruncated: Bool { overviewFullHeight > overviewLimitedHeight + 1 }
    var displayItem: BaseItemDto { detailVM.detailedItem ?? item }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                HStack(alignment: .bottom, spacing: 8){
                    heroImage
                        .background(alignment: .top) {
                            HeroBackdropView(
                                url: detailVM.backdropURL(client: serverViewModel.client),
                                itemID: displayItem.id,
                                blurRadius: 50,
                                isFlipped: true
                            )
                            .offset(y: -400)
                            .ignoresSafeArea(edges: .top)
                        }
                    MediaButtonColumn(item: displayItem, onOptions: { showOptionsSheet = true })
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
                    SkeletonDetailContent(isSeries: displayItem.type == .series)
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
            HStack {
                BackButton()
                Spacer()
                MediaDetailButtonRowTopTrailing {
                    // TODO
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
        .navigationDestination(item: $selectedRelatedItem) { relatedItem in
            MediaDetailView(item: relatedItem)
                .navigationTransition(.zoom(
                    sourceID: relatedZoomID ?? AnyHashable(relatedItem),
                    in: relatedTransition
                ))
        }
        .navigationDestination(item: $selectedEpisode) { episode in
            MediaDetailView(item: episode)
                .navigationTransition(.zoom(
                    sourceID: episodeZoomID ?? AnyHashable(episode),
                    in: episodeTransition
                ))
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
    }
}

#Preview {
    MediaDetailView(item: BaseItemDto(name: "Sample Item"))
        .environment(ServerViewModel())
}
