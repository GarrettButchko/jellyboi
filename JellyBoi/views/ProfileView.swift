//
//  ProfileView.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 8/22/26.
//

import SwiftUI
import BaseColors
import SDWebImageSwiftUI
import JellyfinAPI
import StatusOverlayKit

struct ProfileView: View {
    var onSignOut: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @Environment(ServerViewModel.self) private var serverViewModel

    var body: some View {
        NavigationStack {
            ZStack {
                mainContent
                headerOverlay
            }
            .background(Color.bg.ignoresSafeArea())
            .toolbarVisibility(.hidden, for: .navigationBar)
        }
        .presentationDragIndicator(.visible)
    }

    // MARK: - Header Overlay

    private var headerOverlay: some View {
        VStack {
            HStack {
                Spacer()
                Text("Profile")
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

    // MARK: - Main Content

    private var mainContent: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Profile photo + name
                VStack(spacing: 14) {
                    profileAvatar
                    if let name = serverViewModel.currentUser?.name {
                        Text(name)
                            .font(.system(.title2, design: .rounded, weight: .bold))
                            .foregroundStyle(Color.mainOpp)
                    }
                    if let serverName = serverViewModel.serverName {
                        HStack(spacing: 6) {
                            Image(systemName: "server.rack")
                                .font(.system(size: 12, weight: .semibold))
                            Text(serverName)
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                        }
                        .foregroundStyle(Color.mainOpp.opacity(0.5))
                    }
                }
                .padding(.top, 8)

                // MARK: - Settings
                #if DEBUG
                VStack(alignment: .leading, spacing: 10) {
                    Text("Settings")
                        .font(.system(.footnote, design: .rounded, weight: .bold))
                        .foregroundStyle(Color.mainOpp.opacity(0.45))
                        .textCase(.uppercase)
                        .padding(.horizontal, 4)

                    NavigationLink {
                        DebugSettingsView()
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.orange.opacity(0.15))
                                    .frame(width: 36, height: 36)
                                Image(systemName: "ladybug.fill")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(.orange)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Debug & Empty States")
                                    .font(.system(.body, design: .rounded, weight: .semibold))
                                    .foregroundStyle(Color.mainOpp)
                                Text("Test missing fields and empty rows")
                                    .font(.system(.caption, design: .rounded))
                                    .foregroundStyle(Color.mainOpp.opacity(0.5))
                            }

                            Spacer()

                            if DebugSettings.shared.isAnyActive {
                                Text("\(DebugSettings.shared.activeOverrideCount) active")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundStyle(.orange)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.orange.opacity(0.15), in: Capsule())
                            }

                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.mainOpp.opacity(0.3))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color.mainOpp.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                #endif

                // Sign out
                Button {
                    TransientStatusSignal.shared.pending = StatusMessage(
                        title: "Signed Out",
                        subtitle: "See you next time!",
                        icon: "rectangle.portrait.and.arrow.right",
                        tint: .blue
                    )
                    onSignOut()
                    dismiss()
                } label: {
                    HStack {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Sign Out")
                            .font(.system(.body, design: .rounded, weight: .semibold))
                        Spacer()
                    }
                    .foregroundStyle(Color.blue)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(Color.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 32)
            .frame(maxWidth: .infinity)
            // push content below the gradient header
            .padding(.top, 80)
        }
        .scrollEdgeEffectHidden(true, for: .top)
    }

    // MARK: - Avatar

    @ViewBuilder
    private var profileAvatar: some View {
        if let url = serverViewModel.profileImageURL {
            WebImage(url: url) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                avatarPlaceholder
            }
            .frame(width: 110, height: 110)
            .clipShape(Circle())
        } else {
            avatarPlaceholder
        }
    }

    private var avatarPlaceholder: some View {
        Circle()
            .fill(.ultraThinMaterial)
            .frame(width: 110, height: 110)
            .overlay {
                Image(systemName: "person.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Color.mainOpp.opacity(0.4))
            }
    }
}

#Preview {
    ProfileView()
}
