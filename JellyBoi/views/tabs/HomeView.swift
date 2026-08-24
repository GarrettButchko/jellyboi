//
//  HomeView.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 8/19/26.
//

import SwiftUI
import BaseColors
import JellyfinAPI

struct HomeView: View {
    @Environment(ServerViewModel.self) private var serverViewModel
    @State private var viewModel = HomeViewModel()
    @State private var selectedItem: BaseItemDto?
    @State private var isCarouselInteractive = true
    @Namespace private var zoomTransition

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if let error = viewModel.errorMessage, viewModel.movies.isEmpty {
                        Text(error)
                            .font(.system(.footnote, design: .rounded))
                            .foregroundStyle(Color.mainOpp.opacity(0.6))
                            .padding(.horizontal, 20)
                    } else if viewModel.isLoading && viewModel.movies.isEmpty {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    } else if !viewModel.movies.isEmpty {
                        Carousel(
                            title: "Movies",
                            items: viewModel.movies,
                            namespace: zoomTransition,
                            isInteractive: isCarouselInteractive
                        ) { item in
                            guard let client = serverViewModel.client else { return nil }
                            return viewModel.backdropURL(for: item, client: client)
                        } onSelect: { item in
                            selectedItem = item
                        }
                    }
                }
                .padding(.top, 70)
                .padding(.bottom, 24)
            }
            .navigationDestination(item: $selectedItem) { item in
                MediaDetailView(item: item)
                    .navigationTransition(.zoom(sourceID: item, in: zoomTransition))
            }
            .toolbarVisibility(.hidden, for: .navigationBar)
            .onChange(of: selectedItem) { _, newItem in
                if newItem != nil {
                    // Locked from tap through the push and while the detail is open
                    isCarouselInteractive = false
                } else {
                    // Pop has begun; stay locked until the zoom-out finishes.
                    // The binding nils at pop start, so wait out the transition.
                    Task {
                        try? await Task.sleep(for: .seconds(0.45))
                        isCarouselInteractive = true
                    }
                }
            }
        }
        .background(Color.bg.ignoresSafeArea())
        .overlay(alignment: .topTrailing) {
            ProfileAvatarButton()
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
    }
}

#Preview {
    HomeView()
}
