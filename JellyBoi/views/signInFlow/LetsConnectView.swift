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
    @Environment(ServerViewModel.self) private var serverViewModel
    @State private var viewModel = LetsConnectViewModel()
    @State private var serverURL = ""
    @State private var navigateToServerSignIn = false
    @FocusState private var urlFieldFocused: Bool
    @ScaledMetric(relativeTo: .body) private var inputHeight: CGFloat = 22

    private var isVerified: Bool {
        if case .verified = viewModel.serverCheckState { return true }
        return false
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.bg
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    urlFieldFocused = false
                    hideKeyboard()
                }

            ScrollView {
                VStack(spacing: 0) {
                    Text("Let's Connect!")
                        .font(.system(.title, design: .rounded, weight: .bold))
                        .foregroundStyle(Color.mainOpp)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)

                    contentSection
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .safeAreaInset(edge: .bottom) {
            connectButton
                .padding(.horizontal, 24)
                .padding(.vertical, 8)
                .background(
                    LinearGradient(
                        colors: [Color.bg, Color.clear],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                    .ignoresSafeArea(edges: .bottom)
                )
        }
        .navigationDestination(isPresented: $navigateToServerSignIn) {
            ServerSignInView()
        }
        .onAppear { hideKeyboard() }
        .task { viewModel.startDiscovery() }
        .onDisappear {
            hideKeyboard()
            viewModel.stopDiscovery()
        }
    }

    // MARK: - Content

    private var contentSection: some View {
        VStack(spacing: 16) {
            urlCard
            OrDivider()
            localServersCard
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .animation(.default, value: viewModel.serverCheckState)
        .animation(.default, value: viewModel.discoveredServers.count)
    }

    // MARK: - URL Card

    private var urlCard: some View {
        VStack(spacing: 0) {
            urlRow
        }
        .background {
            RoundedRectangle(cornerRadius: 25, style: .continuous)
                .fill(Color.sub)
        }
    }


    // MARK: - Local Servers Card

    private var localServersCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("Local Servers")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.mainOpp)
                    .padding(.leading, 8)

                if !viewModel.discoveredServers.isEmpty {
                    Text("· \(viewModel.discoveredServers.count) found")
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(Color.mainOpp.opacity(0.3))
                }
            }
            .padding(.leading, 4)

            VStack(spacing: 0) {
                if viewModel.isSearching && viewModel.discoveredServers.isEmpty {
                    HStack(spacing: 10) {
                        ProgressView()
                            .tint(Color.mainOpp.opacity(0.4))
                            .scaleEffect(0.85)
                        Text("Searching…")
                            .font(.system(size: 14, weight: .regular, design: .rounded))
                            .foregroundStyle(Color.mainOpp.opacity(0.35))
                        Spacer()
                    }
                    .padding(16)
                    .transition(.opacity.combined(with: .blurReplace))
                } else if !viewModel.isSearching && viewModel.discoveredServers.isEmpty {
                    HStack {
                        Text("No Local Servers Found")
                            .font(.system(size: 14, weight: .regular, design: .rounded))
                            .foregroundStyle(Color.mainOpp.opacity(0.35))
                        Spacer()
                    }
                    .padding(16)
                    .transition(.opacity.combined(with: .blurReplace))
                } else {
                    ForEach(Array(viewModel.discoveredServers.enumerated()), id: \.element.id) { index, server in
                        if index > 0 {
                            Divider()
                                .overlay(Color.subTwo)
                                .padding(.horizontal, 16)
                        }
                        discoveredServerRow(server)
                    }
                }
            }
            .animation(.easeInOut(duration: 0.4), value: viewModel.isSearching)
            .animation(.easeInOut(duration: 0.4), value: viewModel.discoveredServers.count)
            .background {
                RoundedRectangle(cornerRadius: 25, style: .continuous)
                    .fill(Color.sub)
            }
        }
    }

    private var urlRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "globe")
                .foregroundStyle(Color.appAccent)
                .frame(width: 20, height: 20)

            TextField(text: $serverURL) {
                Text(verbatim: "https://jellyfin.example.com")
                    .foregroundStyle(Color.mainOpp.opacity(0.4))
            }
            .textFieldStyle(.plain)
            .keyboardType(.URL)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .submitLabel(.done)
            .onSubmit {
                if isVerified {
                    handleConnect()
                } else {
                    urlFieldFocused = false
                    hideKeyboard()
                }
            }
            .focused($urlFieldFocused)
            .foregroundStyle(Color.mainOpp)
            .frame(height: inputHeight)
            .onChange(of: serverURL) { _, newValue in
                viewModel.scheduleServerCheck(urlString: newValue)
            }

            checkStateIcon
        }
        .padding(16)
        .contentShape(Rectangle())
        .onTapGesture { urlFieldFocused = true }
    }

    @ViewBuilder
    private var checkStateIcon: some View {
        switch viewModel.serverCheckState {
        case .idle:
            EmptyView()
        case .checking:
            ProgressView()
                .tint(Color.mainOpp.opacity(0.4))
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

    private func discoveredServerRow(_ server: JellyfinClient.PublicServer) -> some View {
        Button {
            serverURL = server.url.absoluteString
            urlFieldFocused = false
            hideKeyboard()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "server.rack")
                    .foregroundStyle(Color.appAccent)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(server.name)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.mainOpp)
                    Text(server.url.absoluteString)
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(Color.mainOpp.opacity(0.4))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.mainOpp.opacity(0.3))
            }
            .padding(16)
        }
    }

    // MARK: - Connect Button

    private func handleConnect() {
        guard case .verified(let name) = viewModel.serverCheckState,
              let url = viewModel.verifiedURL else { return }
        serverViewModel.setServer(url: url, name: name)

        let hadFocus = urlFieldFocused
        urlFieldFocused = false
        KeyboardHelper.dismissThen(wasFocused: hadFocus) {
            navigateToServerSignIn = true
        }
    }

    private var connectButton: some View {
        Button {
            handleConnect()
        } label: {
            Text("Connect")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
        }
        .glassEffect(.regular.tint(Color.appAccent).interactive(), in: RoundedRectangle(cornerRadius: 14))
        .foregroundStyle(.white)
        .disabled(!isVerified)
        .opacity(isVerified ? 1 : 0.4)
    }
}

#Preview {
    NavigationStack {
        LetsConnectView()
    }
    .environment(ServerViewModel())
}
