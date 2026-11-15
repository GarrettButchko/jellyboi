//
//  ServerDetailsView.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 8/29/26.
//

import SwiftUI
import BaseColors
import JellyfinAPI

struct ServerDetailsView: View {
    @Environment(ServerViewModel.self) private var serverViewModel
    @Environment(LibraryViewModel.self) private var libraryViewModel
    @Environment(DownloadsViewModel.self) private var downloadsViewModel

    @State private var isSyncing = false
    @State private var syncError: String?

    var body: some View {
        List {
            // MARK: - Server Info
            Section {
                LabeledContent {
                    Text(serverViewModel.serverName ?? "Jellyfin Server")
                        .foregroundStyle(Color.mainOpp.opacity(0.8))
                } label: {
                    Text("Server Name")
                }

                if let url = serverViewModel.serverURL {
                    LabeledContent {
                        Text(url.absoluteString)
                            .foregroundStyle(Color.mainOpp.opacity(0.8))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } label: {
                        Text("Address")
                    }
                }

                if let version = serverViewModel.serverVersion {
                    LabeledContent {
                        Text(version)
                            .foregroundStyle(Color.mainOpp.opacity(0.8))
                    } label: {
                        Text("Version")
                    }
                }

                LabeledContent {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(serverViewModel.isConnected ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                        Text(serverViewModel.isConnected ? "Connected" : "Disconnected")
                            .foregroundStyle(Color.mainOpp.opacity(0.8))
                    }
                } label: {
                    Text("Status")
                }
            } header: {
                Text("Server")
            }

            // MARK: - User Profile
            Section {
                if let user = serverViewModel.currentUser {
                    LabeledContent {
                        Text(user.name ?? "User")
                            .foregroundStyle(Color.mainOpp.opacity(0.8))
                    } label: {
                        Text("Username")
                    }

                    if let id = user.id {
                        LabeledContent {
                            Text(id)
                                .font(.caption.monospaced())
                                .foregroundStyle(Color.mainOpp.opacity(0.6))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        } label: {
                            Text("User ID")
                        }
                    }

                    LabeledContent {
                        Text(user.hasPassword == true ? "Yes" : "No")
                            .foregroundStyle(Color.mainOpp.opacity(0.8))
                    } label: {
                        Text("Has Password")
                    }
                }
            } header: {
                Text("User Account")
            }

            // MARK: - Library Sync
            Section {
                LabeledContent {
                    Text("\(libraryViewModel.movieIDs.count)")
                        .foregroundStyle(Color.mainOpp.opacity(0.8))
                } label: {
                    Text("Movies Cached")
                }

                LabeledContent {
                    Text("\(libraryViewModel.tvShowIDs.count)")
                        .foregroundStyle(Color.mainOpp.opacity(0.8))
                } label: {
                    Text("TV Shows Cached")
                }

                LabeledContent {
                    Text("\(libraryViewModel.episodeIDs.count)")
                        .foregroundStyle(Color.mainOpp.opacity(0.8))
                } label: {
                    Text("Episodes Cached")
                }

                LabeledContent {
                    Text("\(libraryViewModel.collectionIDs.count)")
                        .foregroundStyle(Color.mainOpp.opacity(0.8))
                } label: {
                    Text("Collections Cached")
                }

                Button {
                    syncLibrary()
                } label: {
                    HStack {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .rotationEffect(.degrees(isSyncing ? 360 : 0))
                            .animation(
                                isSyncing
                                    ? .linear(duration: 1).repeatForever(autoreverses: false)
                                    : .default,
                                value: isSyncing
                            )
                        Text(isSyncing ? "Syncing..." : "Sync Library Now")
                    }
                }
                .disabled(isSyncing || !serverViewModel.isConnected)

                if let syncError {
                    Text(syncError)
                        .font(.caption)
                        .foregroundStyle(Color.red)
                }
            } header: {
                Text("Library Cache")
            }

            // MARK: - Sign Out
            Section {
                Button(role: .destructive) {
                    serverViewModel.signOut()
                } label: {
                    HStack {
                        Spacer()
                        Text("Sign Out")
                            .foregroundStyle(Color.red)
                        Spacer()
                    }
                }
            }
        }
        .navigationTitle("Server Details")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func syncLibrary() {
        guard let client = serverViewModel.client else { return }
        isSyncing = true
        syncError = nil
        Task {
            await libraryViewModel.refresh(using: client)
            isSyncing = false
        }
    }
}
