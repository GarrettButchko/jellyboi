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

private var safeAreaTop: CGFloat {
    UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .first?.keyWindow?.safeAreaInsets.top ?? 0
}

struct CastCrewView: View {
    @State private var viewModel: CastCrewViewModel

    @Environment(ServerViewModel.self) private var serverViewModel
    @Environment(LibraryViewModel.self) private var libraryViewModel
    @Environment(\.horizontalSizeClass) private var sizeClass

    // Overview truncation state
    @State private var isOverviewExpanded = false
    @State private var overviewLimitedHeight: CGFloat = 0
    @State private var overviewFullHeight: CGFloat = 0
    @State private var moreButtonHeight: CGFloat = 0

    // Navigation state
    @State private var selectedMediaItem: BaseItemDto?
    @Namespace private var mediaZoomTransition

    init(person: BaseItemPerson) {
        _viewModel = State(initialValue: CastCrewViewModel(person: person))
    }

    private var isDescriptionTruncated: Bool {
        overviewFullHeight > overviewLimitedHeight + 1
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: sizeClass == .regular ? 160 : 110), spacing: 16)]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Top area: Back button, full-size person image on left, name, birthday & birthplace on right
                VStack{
                    topArea
                    
                    // Overview / description with 3-line truncation and more/less button
                    if let overview = viewModel.overview, !overview.isEmpty {
                        overviewSection(overview)
                            .padding(.horizontal, 16)
                    }
                    
                    ScrollView(.horizontal) {
                        HStack{
                            if let birthday = viewModel.birthDateFormatted {
                                InfoCapsule(icon: "calendar", text: birthday)
                            }
                            
                            if let birthplace = viewModel.birthPlaceFormatted {
                                InfoCapsule(icon: "mappin.and.ellipse", text: birthplace)
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                    .contentMargins(.horizontal, 16)
                }

                // Title: same as the movie rows in the homeview
                Text("Movies & Shows")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color.mainOpp)
                    .padding(.horizontal, 16)
                    .padding(.top, 4)

                // Grid mimicking media tab
                if viewModel.mediaItems.isEmpty {
                    if viewModel.isLoading {
                        SkeletonMediaGrid()
                    } else {
                        EmptyStateView(
                            icon: "film.stack",
                            title: "No Media Found",
                            message: "No movies or TV shows found for \(viewModel.personName)."
                        )
                        .padding(.top, 20)
                    }
                } else {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(viewModel.mediaItems, id: \.id) { item in
                            MediaCard(
                                item: item,
                                posterURL: serverViewModel.client.flatMap { libraryViewModel.posterURL(for: item, client: $0) },
                                namespace: mediaZoomTransition
                            ) {
                                selectedMediaItem = item
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
            .padding(.top, safeAreaTop)
        }
        .overlay(alignment: .topLeading){
            HStack {
                BackButton()
                Spacer()
            }
            .padding(.leading, 16)
        }
        .background(Color.bg.ignoresSafeArea())
        .toolbarVisibility(.hidden, for: .navigationBar)
        .navigationDestination(item: $selectedMediaItem) { item in
            MediaDetailView(item: item)
                .navigationTransition(.zoom(
                    sourceID: item,
                    in: mediaZoomTransition
                ))
        }
        .task {
            await viewModel.loadData(
                client: serverViewModel.client,
                userID: serverViewModel.currentUser?.id
            )
        }
        .refreshable {
            await viewModel.loadData(
                client: serverViewModel.client,
                userID: serverViewModel.currentUser?.id
            )
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
                    .cardShadow()

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

    // MARK: - Person Image

    @ViewBuilder
    private var personImage: some View {
        if let url = viewModel.personImageURL(client: serverViewModel.client) {
            WebImage(
                url: url,
                transaction: Transaction(animation: .easeInOut(duration: 0.3))
            ) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .scaledToFill()
                        .transition(.fade(duration: 0.3))
                } else {
                    personPlaceholder
                }
            }
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

    // MARK: - Overview Section (3-line truncation with more/less)

    private func overviewSection(_ overview: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(overview)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(Color.mainOpp.opacity(0.85))
                .lineLimit(isOverviewExpanded ? nil : 3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.easeInOut(duration: 0.2), value: isOverviewExpanded)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { h in
                    if !isOverviewExpanded { overviewLimitedHeight = h }
                }
                .background(
                    Text(overview)
                        .font(.system(.body, design: .rounded))
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .hidden()
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                            overviewFullHeight = $0
                        }
                )
                .mask {
                    if isDescriptionTruncated && !isOverviewExpanded {
                        VStack(spacing: 0) {
                            Color.black

                            HStack(spacing: 0) {
                                Color.black

                                LinearGradient(
                                    colors: [.black, .clear],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                                .frame(width: 80, height: moreButtonHeight)
                            }
                            .frame(height: moreButtonHeight)
                        }
                    } else {
                        Color.black
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if isDescriptionTruncated && !isOverviewExpanded {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isOverviewExpanded = true
                            }
                        } label: {
                            Text("more")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color.mainOpp.opacity(0.5))
                                .padding(.leading, 32)
                        }
                        .buttonStyle(.plain)
                        .onGeometryChange(for: CGFloat.self) { proxy in
                            proxy.size.height
                        } action: { newHeight in
                            moreButtonHeight = newHeight
                        }
                    }
                }

            if isDescriptionTruncated && isOverviewExpanded {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isOverviewExpanded = false
                    }
                } label: {
                    Text("less")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.mainOpp.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

#Preview {
    CastCrewView(person: BaseItemPerson(name: "Sample Person", role: "Actor"))
        .environment(ServerViewModel())
        .environment(LibraryViewModel())
}
