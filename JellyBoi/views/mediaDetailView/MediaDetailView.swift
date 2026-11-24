//
//  MediaDetailView.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 8/19/26.
//

import SwiftUI
import BaseColors
import SDWebImageSwiftUI
import JellyfinAPI

// MARK: - MediaDetailView

struct MediaDetailView: View {

    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(ServerViewModel.self) var serverViewModel
    @Environment(DownloadManager.self) var downloadManager
    @Environment(PlaybackManager.self) var playbackManager

    @State var detailVM: MediaDetailViewModel
    
    @State var selectedPerson: BaseItemPerson?
    @State var selectedEpisode: BaseItemDto?
    @State var selectedSpecialFeature: BaseItemDto?
    @State var selectedRelatedItem: BaseItemDto?
    @State var selectedCollectionItem: BaseItemDto?
    @State var selectedSeries: BaseItemDto?
    
    @State var showOptionsSheet: Bool = false
    @State var optionsSheetHeight: CGFloat = 0
    
    @State var heroArtworkHeight: CGFloat = 0

    // Zoom transitions
    @Namespace var episodeTransition
    @Namespace var specialFeatureTransition
    @Namespace var relatedTransition
    @Namespace var collectionTransition
    @Namespace var glassNamespace
    @State var episodeZoomID: AnyHashable?
    @State var specialFeatureZoomID: AnyHashable?
    @State var relatedZoomID: AnyHashable?

    init(item: BaseItemDto, itemType: ItemType? = nil) {
        _detailVM = State(initialValue: MediaDetailViewModel(item: item.id ?? "", itemType: itemType))
    }

    init(itemID: String, itemType: ItemType? = nil) {
        _detailVM = State(initialValue: MediaDetailViewModel(item: itemID, itemType: itemType))
    }

    var displayItem: BaseItemDto {
        detailVM.displayItem ?? detailVM.sourceItem ?? BaseItemDto()
    }

    var body: some View {
        @Bindable var detailVM = detailVM
        ScrollToTopScrollView {
            VStack(alignment: .leading, spacing: 0) {
                heroSection

                VStack(alignment: .leading, spacing: 24) {
                    overviewSection

                    if displayItem.type == .series {
                        episodesSection
                    }
                    castSection
                    specialFeaturesSection
                    if displayItem.type == .boxSet {
                        collectionSection
                    }
                    similarItemsSection
                    tagsSection
                    extraInfoSection
                }
                .padding(.top, 16)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.skeleton, value: detailVM.heroAspectRatio)
        }
        .background(Color.bg.ignoresSafeArea())
        .toolbar {
            mediaDetailToolbar
        }
        .navigationTitle("")
        .toolbarTitleDisplayMode(.inline)
        .sheet(isPresented: $showOptionsSheet) {
            optionsSheet
                .presentationDetents(optionsSheetHeight > 0 ? [.height(optionsSheetHeight)] : [.medium])
                .presentationDragIndicator(.visible)
                .presentationSizing(.fitted)
        }
        .alert(
            detailVM.downloadAlertAction == .cancel ? "Cancel Download?" : "Remove Download?",
            isPresented: Binding($detailVM.downloadAlertAction)
        ) {
            if detailVM.downloadAlertAction == .cancel {
                Button("Cancel Download", role: .destructive) {
                    withAnimation(.skeleton) {
                        detailVM.cancelDownload()
                    }
                }
                Button("Keep Downloading", role: .cancel) { }
            } else {
                Button("Remove", role: .destructive) {
                    withAnimation(.skeleton) {
                        detailVM.deleteDownload()
                    }
                }
                Button("Cancel", role: .cancel) { }
            }
        } message: {
            let itemName = detailVM.downloadAlertItemName()
            if detailVM.downloadAlertAction == .cancel {
                Text("Are you sure you want to cancel the download for \"\(itemName)\"? Any progress will be lost.")
            } else {
                Text("Are you sure you want to remove \"\(itemName)\" from your downloads? This cannot be undone.")
            }
        }
        .navigationDestination(item: $selectedPerson) { person in
            CastCrewView(person: person)
        }
        .navigationDestination(item: $selectedSeries) { series in
            MediaDetailView(item: series)
        }
        .navigationDestination(item: $selectedEpisode) { ep in
            MediaDetailView(item: ep, itemType: .episodeWithShow)
                .navigationTransition(.zoom(sourceID: episodeZoomID ?? AnyHashable(ep), in: episodeTransition))
        }
        .navigationDestination(item: $selectedSpecialFeature) { feat in
            MediaDetailView(item: feat)
                .navigationTransition(.zoom(sourceID: specialFeatureZoomID ?? AnyHashable(feat), in: specialFeatureTransition))
        }
        .navigationDestination(item: $selectedRelatedItem) { rel in
            MediaDetailView(item: rel)
                .navigationTransition(.zoom(sourceID: relatedZoomID ?? AnyHashable(rel), in: relatedTransition))
        }
        .navigationDestination(item: $selectedCollectionItem) { col in
            MediaDetailView(item: col)
                .navigationTransition(.zoom(sourceID: AnyHashable(col), in: collectionTransition))
        }
        .task(id: displayItem.id) {
            if let client = serverViewModel.client {
                await detailVM.load(
                    client: client,
                    userID: serverViewModel.currentUser?.id,
                    serverViewModel: serverViewModel
                )
            }
        }
    }
}
