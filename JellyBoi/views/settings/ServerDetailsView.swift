//
//  ServerDetailsView.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 11/04/26.
//

import SwiftUI
import BaseColors
import StatusOverlayKit
import JellyfinAPI

struct ServerDetailsView: View {
    @Environment(ServerViewModel.self) private var serverViewModel
    @Environment(LibraryViewModel.self) private var libraryViewModel
    @Environment(NetworkMonitor.self) private var networkMonitor

    @State private var isSyncing = false

    var body: some View {
        List {
            // MARK: - Server Info
            Section {
                LabeledContent {
                    Text(serverViewModel.serverName ?? "Unknown")
                        .foregroundStyle(Color.mainOpp)
                } label: {
                    Text("Server Name")
                }

                if let urlString = serverViewModel.serverURL?.absoluteString {
                    LabeledContent {
                        Text(urlString)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(Color.mainOpp.opacity(0.8))
                    } label: {
                        Text("Address")
                    }
                }

                LabeledContent {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(networkStatusColor)
                            .frame(width: 8, height: 8)
                        Text(networkStatusText)
                            .foregroundStyle(Color.mainOpp)
                    }
                } label: {
                    Text("Connection Status")
                }
            } header: {
                Text("Server Details")
            }

            // MARK: - User Account
            Section {
                LabeledContent {
                    Text(serverViewModel.currentUser?.name ?? "Unknown")
                        .foregroundStyle(Color.mainOpp)
                } label: {
                    Text("Username")
                }

                if let id = serverViewModel.currentUser?.id {
                    LabeledContent {
                        Text(id)
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(Color.mainOpp.opacity(0.6))
                    } label: {
                        Text("User ID")
                    }
                }

                if let hasPassword = serverViewModel.currentUser?.hasPassword {
                    LabeledContent {
                        Text(hasPassword ? "Protected" : "None")
                            .foregroundStyle(Color.mainOpp.opacity(0.7))
                    } label: {
                        Text("Password")
                    }
                }
            } header: {
                Text("User Account")
            }

            // MARK: - Library Sync
            Section {
                LabeledContent {
                    Text("\(libraryViewModel.movies.count)")
                        .foregroundStyle(Color.mainOpp.opacity(0.8))
                } label: {
                    Text("Movies Cached")
                }

                LabeledContent {
                    Text("\(libraryViewModel.tvShows.count)")
                        .foregroundStyle(Color.mainOpp.opacity(0.8))
                } label: {
                    Text("TV Shows Cached")
                }

                LabeledContent {
                    Text("\(libraryViewModel.episodes.count)")
                        .foregroundStyle(Color.mainOpp.opacity(0.8))
                } label: {
                    Text("Episodes Cached")
                }

                LabeledContent {
                    Text("\(libraryViewModel.collections.count)")
                        .foregroundStyle(Color.mainOpp.opacity(0.8))
                } label: {
                    Text("Collections Cached")
                }

                Button {
                    syncLibrary()
                } label: {
                    HStack {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text("Sync Media Library Now")
                        Spacer()
                        if isSyncing {
                            ProgressView()
                        }
                    }
                }
                .disabled(isSyncing || serverViewModel.client == nil)
            } header: {
                Text("Library Sync")
            } footer: {
                Text("Fetches fresh library items, resume positions, and collections directly from your Jellyfin server.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.bg.ignoresSafeArea())
        .navigationTitle("Server & Network")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Network Status Helpers

    private var networkStatusColor: Color {
        if !networkMonitor.isConnected {
            return .red
        }
        if networkMonitor.isConstrained {
            return .orange
        }
        return .green
    }

    private var networkStatusText: String {
        if !networkMonitor.isConnected {
            return "Offline"
        }
        if networkMonitor.isConstrained {
            return "Low Data Mode"
        }
        if networkMonitor.isExpensive {
            return "Cellular Data"
        }
        return "Connected (Wi-Fi)"
    }

    // MARK: - Actions

    private func syncLibrary() {
        guard let client = serverViewModel.client else { return }
        isSyncing = true

        Task {
            await libraryViewModel.refresh(using: client, userID: serverViewModel.currentUser?.id)
            isSyncing = false
            TransientStatusSignal.shared.pending = StatusMessage(
                title: "Library Synced",
                subtitle: "Latest items updated",
                icon: "arrow.triangle.2.circlepath",
                tint: .green
            )
        }
    }
}
