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
    @StateObject var viewModel = HomeViewModel()
    @State private var selectedItem: BaseItemDto?
    @Namespace private var zoomTransition

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    HStack(alignment: .center) {
                        Text("Home")
                            .font(.system(.title, design: .rounded, weight: .bold))
                            .foregroundStyle(Color.mainOpp)
                        Spacer()
                        ProfileAvatarButton()
                            .padding(.trailing, -20)
                    }
                    .padding(.horizontal, 20)

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
                        }
                    }
                }
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
            .navigationDestination(item: $selectedItem) { item in
                MediaDetailView(item: item)
                    .navigationTransition(.zoom(sourceID: item, in: zoomTransition))
            }
            .toolbarVisibility(.hidden, for: .navigationBar)
        }
        .background(Color.bg.ignoresSafeArea())
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
}

#Preview {
    HomeView()
}
