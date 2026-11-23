//
//  CastCrewView.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 9/22/26.
//

import SwiftUI
import BaseColors
import SDWebImageSwiftUI
import JellyfinAPI

// MARK: - Skeleton Default Items

private let defaultCastCrewMediaItem = BaseItemDto(
    id: "default-cast-crew-media-item",
    name: "Media Title",
    type: .movie
)

private let defaultCastCrewMediaItems: [BaseItemDto] = (0..<12).map { index in
    BaseItemDto(
        id: "default-cast-crew-media-\(index)",
        name: defaultCastCrewMediaItem.name,
        type: defaultCastCrewMediaItem.type
    )
}

private let defaultCastCrewBiography = "This is a placeholder biography describing the life and career of the person for the skeleton loading state across multiple lines."

private let defaultCastCrewBirthday = "January 1, 1970 (55 years old)"

private let defaultCastCrewBirthplace = "Los Angeles, California, USA"

struct CastCrewView: View {
    @State private var viewModel: CastCrewViewModel

    @Environment(ServerViewModel.self) private var serverViewModel
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.openURL) private var openURL

    // Navigation state
    @State private var selectedMediaItem: BaseItemDto?
    @State private var scrollOffset: CGFloat = 0
    @Namespace private var mediaZoomTransition

    init(person: BaseItemPerson) {
        _viewModel = State(initialValue: CastCrewViewModel(person: person))
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: sizeClass == .regular ? 160 : 110), spacing: 16)]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Top area: Back button, full-size person image on left, name, birthday & birthplace on right
                VStack{
                    topArea

                    // Overview / biography with 3-line truncation and more/less button
                    biographyText
                        .padding(.horizontal, 16)
                        .padding(.top, 6)
                        .skeleton(when: isBiographyPlaceholderVisible, value: viewModel.overview)

                    infoCapsules
                        .padding(.top, 6)
                        .skeleton(when: isInfoPlaceholderVisible, value: viewModel.birthDateFormatted)
                }

                // Content: Movies & Shows, and Episodes
                if viewModel.isLoading {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Movies & Shows")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(Color.mainOpp)
                            .padding(.horizontal, 16)

                        MediaGrid(itemIDs: defaultCastCrewMediaItems.compactMap(\.id), namespace: mediaZoomTransition)
                            .skeleton()
                    }
                    .transition(.opacity)
                } else if viewModel.mediaItems.isEmpty && viewModel.episodeItems.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Movies & Shows")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(Color.mainOpp)
                            .padding(.horizontal, 16)

                        EmptyStateView(
                            icon: "film.stack",
                            title: "No Media Found",
                            message: "No movies or TV shows found for \(viewModel.personName)."
                        )
                        .padding(.top, 20)
                    }
                } else {
                    Group {
                        if !viewModel.mediaItems.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Movies & Shows")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(Color.mainOpp)
                                .padding(.horizontal, 16)

                            LazyVGrid(columns: columns, spacing: 16) {
                                ForEach(viewModel.mediaItems, id: \.id) { item in
                                    MediaCard(
                                        item: item,
                                        posterURL: item.posterURL(client: serverViewModel.client),
                                        namespace: mediaZoomTransition,
                                        onSelect: {
                                            selectedMediaItem = item
                                        }
                                    )
                                    .equatable()
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }

                    if !viewModel.episodeItems.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Episodes")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(Color.mainOpp)
                                .padding(.horizontal, 16)

                            LazyVGrid(columns: columns, spacing: 16) {
                                ForEach(viewModel.episodeItems, id: \.id) { episode in
                                    MediaCard(
                                        item: episode,
                                        posterURL: episode.seriesPosterURL(client: serverViewModel.client),
                                        namespace: mediaZoomTransition,
                                        onSelect: {
                                            selectedMediaItem = episode
                                        },
                                        imageAspectRatio: MediaAspectRatio.poster
                                    )
                                    .equatable()
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                    }
                    .transition(.opacity)
                }
            }
            .animation(.skeleton, value: viewModel.isLoading)
            .padding(.bottom, 24)
        }
        .scrollEdgeEffectHidden(scrollOffset <= 0, for: .top)
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top
        } action: { _, newValue in
            scrollOffset = newValue
        }
        .background(Color.bg.ignoresSafeArea())
        .navigationDestination(item: $selectedMediaItem) { item in
            MediaDetailView(item: item)
                .navigationTransition(.zoom(
                    sourceID: item.zoomTransitionID(),
                    in: mediaZoomTransition
                ))
        }
        .task {
            await viewModel.loadData()
        }
        .refreshable {
            await viewModel.loadData()
        }
    }

    // MARK: - Top Area

    private var topArea: some View {
        VStack(alignment: .leading, spacing: 14) {

            // Person image in full size on left, info on right
            HStack(alignment: .top, spacing: 16) {
                personImage
                    .frame(width: 120, height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 0){
                        Text(viewModel.personName)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.mainOpp)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        if let role = viewModel.personRole, !role.isEmpty {
                            Text(role)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color.mainOpp.opacity(0.6))
                        }
                    }

                    
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Biography

    /// The biography is only masked while there is nothing to show yet: once the details
    /// resolve the real text fades in place of the placeholder.
    private var isBiographyPlaceholderVisible: Bool {
        (viewModel.overview ?? "").isEmpty && viewModel.isLoading
    }

    @ViewBuilder
    private var biographyText: some View {
        if let overview = viewModel.overview, !overview.isEmpty {
            ExpandableText(overview, sheetTitle: "Biography")
        } else if viewModel.isLoading {
            ExpandableText(defaultCastCrewBiography, sheetTitle: "Biography")
        }
    }

    // MARK: - Info Capsules

    /// Only show the capsule skeletons when neither birthday nor birthplace has resolved yet.
    private var isInfoPlaceholderVisible: Bool {
        viewModel.birthDateFormatted == nil
            && viewModel.birthPlaceFormatted == nil
            && viewModel.isLoading
    }

    private var infoCapsules: some View {
        ScrollView(.horizontal) {
            HStack {
                if let birthday = viewModel.birthDateFormatted {
                    InfoCapsule(icon: "calendar", text: birthday)
                } else if viewModel.isLoading {
                    InfoCapsule(icon: "calendar", text: defaultCastCrewBirthday)
                }

                if let birthplace = viewModel.birthPlaceFormatted {
                    Button {
                        openMaps(for: birthplace)
                    } label: {
                        InfoCapsule(icon: "mappin.and.ellipse", text: birthplace)
                    }
                    .buttonStyle(.plain)
                } else if viewModel.isLoading {
                    InfoCapsule(icon: "mappin.and.ellipse", text: defaultCastCrewBirthplace)
                }
            }
        }
        .scrollIndicators(.hidden)
        .contentMargins(.horizontal, 16)
    }

    // MARK: - Person Image

    @ViewBuilder
    private var personImage: some View {
        if let url = viewModel.personImageURL() {
            WebImage(
                url: url,
                transaction: Transaction(animation: .easeInOut(duration: 0.3))
            ) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .scaledToFill()
                        .transition(.fade(duration: 0.3))
                } else if viewModel.isLoading {
                    SkeletonBlock(cornerRadius: 16)
                } else {
                    personPlaceholder
                }
            }
        } else if viewModel.isLoading {
            SkeletonBlock(cornerRadius: 16)
        } else {
            personPlaceholder
        }
    }

    private var personPlaceholder: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color.sub)
            .overlay {
                Image(systemName: "person.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Color.subFour)
            }
    }

    // MARK: - Actions

    private func openMaps(for location: String) {
        if let url = viewModel.mapsURL(for: location) {
            openURL(url)
        }
    }
}

#Preview {
    CastCrewView(person: BaseItemPerson(name: "Sample Person", role: "Actor"))
        .environment(ServerViewModel())
        .environment(LibraryViewModel())
}
