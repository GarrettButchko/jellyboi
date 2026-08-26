//
//  HomeView.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 8/19/26.
//

import SwiftUI
import BaseColors
import JellyfinAPI
import SDWebImageSwiftUI

struct HomeView: View {
    @Environment(ServerViewModel.self) private var serverViewModel
    @StateObject var viewModel = HomeViewModel()
    @State private var selectedItem: BaseItemDto?
    @Namespace private var zoomTransition

    @State private var scrollOffset: CGFloat = 0
    @State private var headerHeight: CGFloat = 120
    @State private var heroItem: BaseItemDto?
    @State private var safeAreaTop: CGFloat = 0

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                ScrollView {
                    VStack(alignment: .leading) {
                        if let error = viewModel.errorMessage, viewModel.movies.isEmpty {
                            Text(error)
                                .font(.system(.footnote, design: .rounded))
                                .foregroundStyle(Color.mainOpp.opacity(0.6))
                                .padding(.horizontal, 20)
                        } else {
                            Carousel(
                                title: "Movies",
                                namespace: zoomTransition
                            ) { item in
                                guard let client = serverViewModel.client else { return nil }
                                return viewModel.backdropURL(for: item, client: client)
                            } onSelect: { item in
                                selectedItem = item
                            } onSnap: { index, item in
                                withAnimation(.smooth(duration: 0.4)) { heroItem = item }
                                if let client = serverViewModel.client {
                                    viewModel.prefetchBackdrops(around: index, client: client)
                                    viewModel.prefetchPosters(around: index, client: client)
                                }
                            }

                            if !viewModel.recommended.isEmpty {
                                HomeSectionRow(
                                    title: "Recommended",
                                    items: viewModel.recommended,
                                    namespace: zoomTransition,
                                    selectedItem: $selectedItem
                                ) { item in
                                    guard let client = serverViewModel.client else { return nil }
                                    return viewModel.posterURL(for: item, client: client)
                                }
                                .padding(.top, 20)
                            }

                            if !viewModel.recentlyAdded.isEmpty {
                                HomeSectionRow(
                                    title: "Recently Added",
                                    items: viewModel.recentlyAdded,
                                    namespace: zoomTransition,
                                    selectedItem: $selectedItem
                                ) { item in
                                    guard let client = serverViewModel.client else { return nil }
                                    return viewModel.posterURL(for: item, client: client)
                                }
                                .padding(.top, 20)
                            }

                            if !viewModel.quality480p.isEmpty {
                                HomeSectionRow(
                                    title: "DVD",
                                    items: viewModel.quality480p,
                                    namespace: zoomTransition,
                                    selectedItem: $selectedItem
                                ) { item in
                                    guard let client = serverViewModel.client else { return nil }
                                    return viewModel.posterURL(for: item, client: client)
                                }
                                .padding(.top, 20)
                            }

                            if !viewModel.quality1080p.isEmpty {
                                HomeSectionRow(
                                    title: "Blu-ray",
                                    items: viewModel.quality1080p,
                                    namespace: zoomTransition,
                                    selectedItem: $selectedItem
                                ) { item in
                                    guard let client = serverViewModel.client else { return nil }
                                    return viewModel.posterURL(for: item, client: client)
                                }
                                .padding(.top, 20)
                            }
                        }
                    }
                    .padding(.bottom, 24)
                    .background(alignment: .top) {
                        heroBackdrop
                            .offset(y: -(headerHeight + safeAreaTop + 500))
                            .ignoresSafeArea(edges: .top)
                    }
                }
                .navigationDestination(item: $selectedItem) { item in
                    MediaDetailView(item: item)
                        .navigationTransition(.zoom(sourceID: item, in: zoomTransition))
                }
                .toolbarVisibility(.hidden, for: .navigationBar)
                .contentMargins(.top, headerHeight, for: .scrollContent)
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentOffset.y + geometry.contentInsets.top
                } action: { _, newValue in
                    scrollOffset = newValue
                }
                

                TabPageHeader(title: "Home", scrollOffset: scrollOffset, headerHeight: $headerHeight, showGradient: false)
            }
            
        }
        .background(Color.bg.ignoresSafeArea())
        .background {
            GeometryReader { geo in
                Color.clear.onAppear { safeAreaTop = geo.safeAreaInsets.top }
            }
        }
        .task {
            if let client = serverViewModel.client {
                await viewModel.load(using: client)
            }
        }
        .onChange(of: serverViewModel.client != nil) { _, hasClient in
            guard hasClient, let client = serverViewModel.client else { return }
            Task { await viewModel.load(using: client) }
        }
        .environment(viewModel)
    }

    @ViewBuilder
    private var heroBackdrop: some View {
        if let item = heroItem ?? viewModel.movies.first,
           let client = serverViewModel.client,
           let url = viewModel.posterURL(for: item, client: client) {
            WebImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: { Color.clear }
            .frame(maxWidth: .infinity)
            .frame(height: 1150)
            .blur(radius: 30)
            .opacity(1)
            .mask(
                LinearGradient(
                    colors: [.black, .black.opacity(0.5), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .ignoresSafeArea(edges: .top)
            .id(item.id)
            .transition(.opacity)
            .animation(.smooth(duration: 0.5), value: item.id)
        }
    }
}



// MARK: - Section Row

private struct HomeSectionRow: View {
    let title: String
    let items: [BaseItemDto]
    let namespace: Namespace.ID
    @Binding var selectedItem: BaseItemDto?
    let posterURL: (BaseItemDto) -> URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Color.mainOpp)
                .padding(.horizontal, 16)

            ScrollView(.horizontal) {
                LazyHStack(spacing: 16) {
                    ForEach(items, id: \.id) { item in
                        MediaCard(
                            item: item,
                            posterURL: posterURL(item),
                            namespace: namespace
                        ) {
                            selectedItem = item
                        }
                        .frame(width: 110)
                    }
                }
                .padding(.horizontal, 16)
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
        }
    }
}

#Preview {
    HomeView()
}
