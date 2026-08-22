//
//  LetsConnectView.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 8/21/26.
//

import SwiftUI
import BaseColors
import StatusOverlayKit
import JellyfinAPI

struct LetsConnectView: View {
    @EnvironmentObject var viewManager: ViewManager
    @State private var viewModel = LetsConnectViewModel()
    @State private var serverURL = ""
    @FocusState private var urlFieldFocused: Bool

    private var isVerified: Bool {
        if case .verified = viewModel.serverCheckState { return true }
        return false
    }

    @State private var contentMargins: CGFloat = 70
    @State private var viewContentHeight: CGFloat = 0

    var body: some View {
        ZStack {
            mainContent
                .contentMargins(.top, contentMargins)
                .contentMargins(.bottom, contentMargins)

            headerOverlay
            bottomButton
        }
        .background {
            GeometryReader { proxy in
                Color.bg.ignoresSafeArea()
                    .task(id: proxy.size) {
                        withAnimation {
                            viewContentHeight = proxy.size.height - contentMargins * 2
                        }
                    }
            }
        }
        .task { viewModel.startDiscovery() }
        .onDisappear { viewModel.stopDiscovery() }
        .presentationDragIndicator(.visible)
    }

    // MARK: - Header

    private var headerOverlay: some View {
        VStack {
            HStack {
                Spacer()
                Text("Let's Connect!")
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .foregroundStyle(Color.mainOpp)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .padding(.top, 20)
                Spacer()
            }
            .padding(.bottom)
            .background(
                LinearGradient(
                    colors: [Color.bg, Color.clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea(edges: .top)
            )
            Spacer()
        }
    }

    // MARK: - Bottom Button

    private var bottomButton: some View {
        VStack {
            Spacer()
            Button {
                if case .verified(let name) = viewModel.serverCheckState {
                    TransientStatusSignal.shared.pending = StatusMessage(
                        title: "Connected!",
                        subtitle: "Successfully reached \(name).",
                        icon: "checkmark.circle.fill",
                        tint: .green
                    )
                    viewManager.navigateToServerSignIn()
                }
            } label: {
                Text("Connect")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .glassEffect(
                .regular.tint(.accent).interactive(),
                in: RoundedRectangle(cornerRadius: 14)
            )
            .foregroundStyle(.white)
            .disabled(!isVerified)
            .opacity(isVerified ? 1 : 0.4)
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
            .safeAreaPadding(.bottom, 10)
            .background(
                LinearGradient(
                    colors: [Color.bg, Color.clear],
                    startPoint: .bottom,
                    endPoint: .top
                )
                .ignoresSafeArea(edges: .bottom)
            )
        }
    }

    // MARK: - Main Content

    private var mainContent: some View {
        ScrollView {
            VStack {
                VStack(spacing: 24) {
                    VStack(spacing: 6) {
                        Text("Enter your server URL")
                            .font(.system(.title3, design: .rounded, weight: .bold))
                            .foregroundStyle(Color.mainOpp)

                        Text("Connect to your Jellyfin server to get started")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.mainOpp.opacity(0.5))
                            .multilineTextAlignment(.center)
                    }

                    VStack(spacing: 20) {
                        urlTextField
                        actionDivider
                        localServerSection
                    }
                }
                .padding(.vertical, 32)
                .padding(.horizontal, 20)
                .background {
                    RoundedRectangle(cornerRadius: 25, style: .continuous)
                        .fill(Color.sub)
                        .cardShadow()
                }
            }
            .padding(.horizontal, 24)
            .frame(minHeight: viewContentHeight, alignment: .center)
        }
    }

    // MARK: - URL Text Field

    private var urlTextField: some View {
        HStack(spacing: 10) {
            Image(systemName: "globe")
                .foregroundStyle(.accent)
                .frame(width: 20)

            TextField(text: $serverURL) {
                Text(verbatim: "https://jellyfin.example.com")
                    .foregroundStyle(Color.subOpp.opacity(0.5))
            }
            .keyboardType(.URL)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .focused($urlFieldFocused)
            .foregroundStyle(Color.mainOpp)
            .onChange(of: serverURL) { _, newValue in
                viewModel.scheduleServerCheck(urlString: newValue)
            }

            checkStateIcon
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        }
        .contentShape(Rectangle())
        .onTapGesture { urlFieldFocused = true }
        .animation(.default, value: viewModel.serverCheckState)
    }

    @ViewBuilder
    private var checkStateIcon: some View {
        switch viewModel.serverCheckState {
        case .idle:
            EmptyView()
        case .checking:
            ProgressView()
                .tint(Color.subOpp.opacity(0.5))
                .scaleEffect(0.8)
        case .verified:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .transition(.scale.combined(with: .opacity))
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
                .transition(.scale.combined(with: .opacity))
        }
    }

    // MARK: - OR Divider

    private var actionDivider: some View {
        HStack {
            Rectangle().fill(.separator).frame(height: 1)
            Text("OR")
                .font(.caption2)
                .fontWeight(.black)
                .foregroundStyle(Color.subThree)
            Rectangle().fill(.separator).frame(height: 1)
        }
        .padding(.horizontal, 40)
    }

    // MARK: - Local Server Section

    private var localServerSection: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "server.rack")
                    .font(.system(size: 22))
                    .foregroundStyle(.accent)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Local Servers")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.mainOpp)
                    Text(viewModel.isSearching ? "Searching your network..." : "\(viewModel.discoveredServers.count) found")
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(Color.subOpp.opacity(0.5))
                        .animation(.default, value: viewModel.isSearching)
                }

                Spacer()

                if viewModel.isSearching {
                    ProgressView()
                        .tint(Color.subOpp.opacity(0.5))
                }
            }
            .padding(14)

            if !viewModel.discoveredServers.isEmpty {
                Divider().padding(.horizontal, 14)

                ForEach(viewModel.discoveredServers) { server in
                    Button {
                        serverURL = server.url.absoluteString
                        urlFieldFocused = false
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(.accent)
                                .frame(width: 28)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(server.name)
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .foregroundStyle(Color.mainOpp)
                                Text(server.url.absoluteString)
                                    .font(.system(size: 12, weight: .regular, design: .rounded))
                                    .foregroundStyle(Color.subThree)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.subThree)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                    }

                    if server.id != viewModel.discoveredServers.last?.id {
                        Divider().padding(.horizontal, 14)
                    }
                }
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        }
        .animation(.default, value: viewModel.discoveredServers.count)
    }
}

#Preview {
    GetStartedView()
}
