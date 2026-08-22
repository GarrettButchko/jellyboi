//
//  LetsConnectView.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 8/21/26.
//

import SwiftUI
import BaseColors
import JellyfinAPI

struct LetsConnectView: View {
    @State private var viewModel = LetsConnectViewModel()
    @State private var serverURL = ""
    @FocusState private var urlFieldFocused: Bool

    private var isValidURL: Bool {
        guard let url = URL(string: serverURL),
              let scheme = url.scheme,
              (scheme == "http" || scheme == "https"),
              let host = url.host, !host.isEmpty else { return false }
        return true
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
        .presentationDragIndicator(.visible)
        .task { viewModel.startDiscovery() }
        .onDisappear { viewModel.stopDiscovery() }
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
            .disabled(!isValidURL)
            .opacity(isValidURL ? 1 : 0.4)
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
                    .foregroundStyle(Color.subThree)
            }
            .keyboardType(.URL)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .focused($urlFieldFocused)
            .foregroundStyle(Color.mainOpp)
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        }
        .contentShape(Rectangle())
        .onTapGesture { urlFieldFocused = true }
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
            // Header row
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
                        .foregroundStyle(Color.subFour)
                        .animation(.default, value: viewModel.isSearching)
                }

                Spacer()

                if viewModel.isSearching {
                    ProgressView()
                        .tint(Color.subThree)
                }
            }
            .padding(14)

            // Discovered servers
            if !viewModel.discoveredServers.isEmpty {
                Divider()
                    .padding(.horizontal, 14)

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
