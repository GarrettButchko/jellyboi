//
//  ServerSignInView.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 8/21/26.
//

import SwiftUI
import BaseColors
import StatusOverlayKit

private let overlaySpring: Animation = .spring(response: 0.4, dampingFraction: 0.65)

struct ServerSignInView: View {
    private enum Field: Hashable {
        case username
        case password
    }

    @Environment(ViewManager.self) private var viewManager
    @Environment(ServerViewModel.self) private var serverViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = ServerSignInViewModel()
    @State private var showQuickConnectOverlay = false
    @State private var isOverlayActive = false
    @FocusState private var focusedField: Field?
    @ScaledMetric(relativeTo: .body) private var inputHeight: CGFloat = 22

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.bg
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    focusedField = nil
                    hideKeyboard()
                }

            ScrollView {
                VStack(spacing: 0) {
                    Text("Sign In")
                        .font(.system(.title, design: .rounded, weight: .bold))
                        .foregroundStyle(Color.mainOpp)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                    credentialsSection
                    Spacer()
                }
                .padding(.top, 60)
            }
            .scrollDismissesKeyboard(.interactively)

            topSection

            quickConnectOverlay
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { hideKeyboard() }
        .onDisappear { hideKeyboard() }
        .animation(overlaySpring, value: showQuickConnectOverlay)
        .onChange(of: viewModel.didAuthenticate) { _, authenticated in
            if authenticated {
                let hadFocus = focusedField != nil
                focusedField = nil
                KeyboardHelper.dismissThen(wasFocused: hadFocus) {
                    if let token = viewModel.savedToken {
                        serverViewModel.saveSession(token: token)
                    }
                    serverViewModel.currentUser = viewModel.authenticatedUser
                    withAnimation(overlaySpring) {
                        showQuickConnectOverlay = false
                    } completion: {
                        isOverlayActive = false
                    }
                    viewManager.completeSignIn()
                }
            }
        }
    }

    // MARK: - Top Bar

    private var topSection: some View {
        ZStack(alignment: .center) {
            HStack {
                BackButton {
                    viewModel.stopQuickConnect()
                    let hadFocus = focusedField != nil
                    focusedField = nil
                    KeyboardHelper.dismissThen(wasFocused: hadFocus) {
                        dismiss()
                    }
                }
                .padding(.leading, 20)

                Spacer()
            }

            if let name = serverViewModel.serverName {
                HStack {
                    Image(systemName: "server.rack")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.accent)
                    Text(name)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.accent)
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
                .background {
                    RoundedRectangle(cornerRadius: 25)
                        .fill(Color.appAccent.opacity(0.1))
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Credentials Section

    private var credentialsSection: some View {
        VStack(spacing: 16) {
            // Username + password wrapped in a card
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "person")
                        .foregroundStyle(.accent)
                        .frame(width: 20, height: 20)
                    TextField("Username", text: $viewModel.username)
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .focused($focusedField, equals: .username)
                        .submitLabel(.next)
                        .onSubmit {
                            focusedField = .password
                        }
                        .foregroundStyle(Color.mainOpp)
                        .frame(height: inputHeight)
                }
                .padding(16)
                .contentShape(Rectangle())
                .onTapGesture {
                    focusedField = .username
                }

                Divider()
                    .overlay(Color.mainOpp.opacity(0.15))
                    .padding(.horizontal, 16)

                HStack(spacing: 10) {
                    Image(systemName: "lock")
                        .foregroundStyle(.accent)
                        .frame(width: 20, height: 20)
                    SecureField("Password", text: $viewModel.password)
                        .textFieldStyle(.plain)
                        .focused($focusedField, equals: .password)
                        .submitLabel(.go)
                        .onSubmit {
                            if !viewModel.username.isEmpty && viewModel.signInState != .loading {
                                handleSignIn()
                            } else {
                                focusedField = nil
                                hideKeyboard()
                            }
                        }
                        .foregroundStyle(Color.mainOpp)
                        .frame(height: inputHeight)
                }
                .padding(16)
                .contentShape(Rectangle())
                .onTapGesture {
                    focusedField = .password
                }
            }
            .background {
                RoundedRectangle(cornerRadius: 25, style: .continuous)
                    .fill(Color.sub)
            }

            // Error
            if case .error(let message) = viewModel.signInState {
                Text(message)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            // Sign In button
            Button {
                handleSignIn()
            } label: {
                Group {
                    if case .loading = viewModel.signInState {
                        ProgressView().tint(.white)
                    } else {
                        Text("Sign In")
                            .font(.system(size: 17, weight: .semibold))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            }
            .glassEffect(.regular.tint(.accent).interactive(), in: RoundedRectangle(cornerRadius: 14))
            .foregroundStyle(.white)
            .disabled(viewModel.username.isEmpty || viewModel.signInState == .loading)
            .opacity(viewModel.username.isEmpty ? 0.4 : 1)

            // Forgot password
            if let url = serverViewModel.serverURL {
                Link(destination: url) {
                    Text("Forgot Password?")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.mainOpp.opacity(0.5))
                }
            }

            OrDivider()

            // Quick Connect button
            Button {
                focusedField = nil
                hideKeyboard()
                if let client = serverViewModel.client {
                    isOverlayActive = true
                    viewModel.startQuickConnect(using: client)
                    withAnimation(overlaySpring) {
                        showQuickConnectOverlay = true
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "qrcode")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Quick Connect")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            }
            .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 14))
            .foregroundStyle(Color.mainOpp)
            .disabled(isOverlayActive)
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .animation(.default, value: viewModel.signInState)
    }

    private func handleSignIn() {
        guard let client = serverViewModel.client else { return }
        focusedField = nil
        hideKeyboard()
        Task { await viewModel.signIn(using: client) }
    }

    // MARK: - Quick Connect Overlay

    private var quickConnectOverlay: some View {
        ZStack {
            if showQuickConnectOverlay {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(overlaySpring) {
                            showQuickConnectOverlay = false
                        } completion: {
                            isOverlayActive = false
                        }
                        viewModel.stopQuickConnect()
                    }
                    .transition(.opacity)

                VStack(spacing: 24) {
                    switch viewModel.quickConnectState {
                    case .idle:
                        ProgressView()
                            .scaleEffect(1.4)
                            .tint(.secondary)
                        Text("Starting Quick Connect…")
                            .font(.system(.subheadline, design: .rounded, weight: .medium))
                            .foregroundStyle(.secondary)

                    case .polling(let code):
                        VStack(spacing: 10) {
                            Text(code)
                                .font(.system(size: 48, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.mainOpp)
                                .tracking(8)

                            Text("Enter this code on your Jellyfin\nserver's web interface.")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)

                            HStack(spacing: 6) {
                                ProgressView()
                                    .scaleEffect(0.75)
                                    .tint(.secondary)
                                Text("Waiting for approval…")
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.top, 4)
                        }

                    case .error(let message):
                        VStack(spacing: 10) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 36))
                                .foregroundStyle(.red)
                            Text(message)
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                            Button("Try Again") {
                                if let client = serverViewModel.client {
                                    viewModel.startQuickConnect(using: client)
                                }
                            }
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(.accent)
                        }
                    }
                }
                .padding(28)
                .background {
                    RoundedRectangle(cornerRadius: 38, style: .continuous)
                        .fill(.ultraThinMaterial)
                }
                .padding(.horizontal, 30)
                .transition(.scale(scale: 0.92).combined(with: .opacity))
                .animation(overlaySpring, value: viewModel.quickConnectState)

                VStack {
                    Spacer()
                    Text("Tap anywhere to close")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.bottom, 20)
                        .safeAreaPadding(.bottom)
                }
                .allowsHitTesting(false)
                .transition(.opacity)
            }
        }
        .allowsHitTesting(showQuickConnectOverlay)
    }
}

#Preview {
    ServerSignInView()
        .environment(ViewManager())
}
