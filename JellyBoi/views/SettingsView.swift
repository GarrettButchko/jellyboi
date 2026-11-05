//
//  SettingsView.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 8/22/26.
//

import SwiftUI
import BaseColors
import LoggingKit
import SDWebImageSwiftUI
import StatusOverlayKit
import JellyfinAPI

struct SettingsView: View {
    var onSignOut: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @Environment(ServerViewModel.self) private var serverViewModel

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - User Profile Header
                Section {
                    HStack(spacing: 16) {
                        profileAvatar

                        VStack(alignment: .leading, spacing: 4) {
                            Text(serverViewModel.currentUser?.name ?? "User")
                                .font(.system(.title2, design: .rounded, weight: .bold))
                                .foregroundStyle(Color.mainOpp)

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
                    }
                    .padding(.vertical, 6)
                }

                // MARK: - Settings Section
                Section {
                    // Storage & Cache
                    NavigationLink {
                        StorageSettingsView()
                    } label: {
                        settingsRow(
                            icon: "internaldrive.fill",
                            color: .purple,
                            title: "Storage & Cache",
                            subtitle: "Image cache and offline media storage"
                        )
                    }

                    // Server & Network
                    NavigationLink {
                        ServerDetailsView()
                    } label: {
                        settingsRow(
                            icon: "server.rack",
                            color: .blue,
                            title: "Server & Network",
                            subtitle: serverViewModel.serverName ?? "Connection and sync details"
                        )
                    }

                    // Diagnostics & Logs
                    NavigationLink {
                        DiagnosticsView()
                    } label: {
                        settingsRow(
                            icon: "stethoscope",
                            color: .teal,
                            title: "Diagnostics & Logs",
                            subtitle: "View logs and export diagnostics"
                        )
                    }

                    // About JellyBoi
                    NavigationLink {
                        AboutSettingsView()
                    } label: {
                        settingsRow(
                            icon: "info.circle.fill",
                            color: .indigo,
                            title: "About JellyBoi",
                            subtitle: "Version and open source credits"
                        )
                    }

                    #if DEBUG
                    // Debug & Empty States
                    NavigationLink {
                        DebugSettingsView()
                    } label: {
                        settingsRow(
                            icon: "ladybug.fill",
                            color: .orange,
                            title: "Debug & Empty States",
                            subtitle: "Test missing fields and empty rows",
                            trailingBadge: DebugSettings.shared.isAnyActive ? "\(DebugSettings.shared.activeOverrideCount) active" : nil
                        )
                    }
                    #endif
                }

                // MARK: - Account Actions
                Section {
                    Button(role: .destructive) {
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
                        .foregroundStyle(Color.red)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.bg.ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                }
            }
        }
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.bg)
    }

    // MARK: - Settings Row

    @ViewBuilder
    private func settingsRow(
        icon: String,
        color: Color,
        title: String,
        subtitle: String,
        trailingBadge: String? = nil
    ) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(color.gradient)
                    .frame(width: 30, height: 30)

                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .foregroundStyle(Color.mainOpp)

                Text(subtitle)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color.mainOpp.opacity(0.6))
                    .lineLimit(1)
            }

            if let badge = trailingBadge {
                Spacer()
                Text(badge)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.orange.opacity(0.15), in: Capsule())
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Profile Avatar

    private var profileAvatar: some View {
        Group {
            if let url = serverViewModel.profileImageURL {
                WebImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    defaultAvatar
                }
                .frame(width: 56, height: 56)
                .clipShape(Circle())
            } else {
                defaultAvatar
            }
        }
    }

    private var defaultAvatar: some View {
        Image(systemName: "person.circle.fill")
            .resizable()
            .scaledToFit()
            .frame(width: 56, height: 56)
            .foregroundStyle(Color.mainOpp.opacity(0.3))
    }
}
