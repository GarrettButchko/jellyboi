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

    @Environment(ServerViewModel.self) var serverViewModel
    @Environment(LibraryViewModel.self) var libraryViewModel
    @Environment(\.verticalSizeClass) var verticalSizeClass

    @State var detailVM = MediaDetailViewModel()
    @State var isOverviewExpanded = false
    @State var overviewLimitedHeight: CGFloat = 0
    @State var overviewFullHeight: CGFloat = 0
    @State var showOptionsSheet = false
    @State var selectedRelatedItem: BaseItemDto?
    @Namespace var relatedTransition
    @State var relatedZoomID: AnyHashable?
    @State var moreButtonHeight: CGFloat = 0

    var isDescriptionTruncated: Bool { overviewFullHeight > overviewLimitedHeight + 1 }
    var displayItem: BaseItemDto { detailVM.detailedItem ?? item }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                heroImage
                    .background(alignment: .top) {
                        heroBackdrop
                            .offset(y: -400)
                            .ignoresSafeArea(edges: .top)
                    }
                    .safeAreaPadding(.top)
                
                buttonRow
                    .padding([.horizontal, .top], 16)

                VStack(alignment: .leading, spacing: 24) {

                    if let overview = displayItem.overview, !overview.isEmpty {
                        overviewSection(overview)
                            .padding(.horizontal, 20)
                    }

                    infoChipsScrollView

                    let actors = (displayItem.people ?? []).filter { $0.type == .actor }
                    if !actors.isEmpty {
                        castSection(actors)
                    }

                    if !detailVM.similarItems.isEmpty {
                        HomeSectionRow(
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
                .padding(.top, 20)
                .padding(.bottom, 48)
            }
        }
        .ignoresSafeArea(edges: .top)
        .background(Color.bg.ignoresSafeArea())
        .toolbarVisibility(.hidden, for: .navigationBar)
        .overlay(alignment: .topLeading) {
            BackButton()
                .padding(.leading, 16)
                .padding(.top, 4)
                .safeAreaPadding(.top)
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
        .task {
            guard let client = serverViewModel.client, item.id != nil else { return }
            await detailVM.load(
                item: item,
                client: client,
                userID: serverViewModel.currentUser?.id
            )
        }
    }
}

#Preview {
    MediaDetailView(item: BaseItemDto(name: "Sample Item"))
        .environment(ServerViewModel())
}
