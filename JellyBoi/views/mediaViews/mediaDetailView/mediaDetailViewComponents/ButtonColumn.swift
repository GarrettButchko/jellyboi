//
//  MediaButtonColumn.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 8/25/26.
//

import SwiftUI
import BaseColors
import JellyfinAPI

extension MediaDetailView {

    var buttonColumn: some View {
        VStack(spacing: 12) {
            if detailVM.shouldShowOptionsButton(libraryViewModel: libraryViewModel) {
                Button {
                    showOptionsSheet = true
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.mainOpp)
                        .frame(width: 50, height: 50)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: Circle())
            }

            GlassEffectContainer(spacing: 8) {
                VStack(spacing: 8) {
                    if detailVM.progressVisible {
                        progressRingButton
                            .glassEffect(.regular.tint(.mainOpp.opacity(0.9)).interactive())
                            .glassEffectUnion(id: "colBut", namespace: glassNamespace)
                            .transition(.scale(scale: 0.8).combined(with: .opacity))
                    }
                    Button {
                        detailVM.handlePlayTap(
                            playbackManager: playbackManager,
                            serverViewModel: serverViewModel,
                            libraryViewModel: libraryViewModel
                        )
                    } label: {
                        Image(systemName: "play.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.main)
                            .frame(width: 50, height: 50)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.tint(.mainOpp.opacity(0.9)).interactive())
                    .glassEffectUnion(id: "colBut", namespace: glassNamespace)
                    .contentShape(.contextMenuPreview, Circle())
                    .contextMenu {
                        playbackMenuContent
                    }
                }
            }
        }
        .animation(.smooth(duration: 0.3), value: detailVM.progressVisible)
    }

    // MARK: - Progress Ring Button

    private var progressRingButton: some View {
        Menu {
            playbackMenuContent
        } label: {
            ZStack {
                Circle()
                    .stroke(Color.main.opacity(0.1), lineWidth: 5)
                    .frame(width: 35, height: 35)

                if detailVM.isWatched {
                    Circle()
                        .stroke(Color.accent, lineWidth: 5)
                        .frame(width: 35, height: 35)

                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.main)
                } else {
                    Circle()
                        .trim(from: 0, to: detailVM.progressValue)
                        .stroke(Color.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 35, height: 35)

                    Text(detailVM.percentText)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.main)
                }
            }
            .frame(width: 50, height: 50)
        }
    }

    // MARK: - Playback Menu Content

    @ViewBuilder
    private var playbackMenuContent: some View {
        Section {
            if detailVM.isInProgress {
                Button {
                    detailVM.playMedia(
                        fromBeginning: false,
                        playbackManager: playbackManager,
                        serverViewModel: serverViewModel,
                        libraryViewModel: libraryViewModel
                    )
                } label: {
                    Label("Continue watching", systemImage: "play.fill")
                }

                Button {
                    detailVM.playMedia(
                        fromBeginning: true,
                        playbackManager: playbackManager,
                        serverViewModel: serverViewModel,
                        libraryViewModel: libraryViewModel
                    )
                } label: {
                    Label("Start from beginning", systemImage: "arrow.counterclockwise")
                }

                Button(role: .destructive) {
                    detailVM.resetProgress(serverViewModel: serverViewModel)
                } label: {
                    Label("Reset Progress", systemImage: "xmark.circle")
                }
            } else if detailVM.isWatched {
                Button {
                    detailVM.playMedia(
                        fromBeginning: true,
                        playbackManager: playbackManager,
                        serverViewModel: serverViewModel,
                        libraryViewModel: libraryViewModel
                    )
                } label: {
                    Label("Start from beginning", systemImage: "arrow.counterclockwise")
                }

                Button(role: .destructive) {
                    detailVM.resetProgress(serverViewModel: serverViewModel)
                } label: {
                    Label("Reset Progress", systemImage: "xmark.circle")
                }
            } else {
                Button {
                    detailVM.playMedia(
                        fromBeginning: false,
                        playbackManager: playbackManager,
                        serverViewModel: serverViewModel,
                        libraryViewModel: libraryViewModel
                    )
                } label: {
                    Label("Start", systemImage: "play.fill")
                }
            }
        } header: {
            if !detailVM.contextMenuTitle.isEmpty {
                Text(detailVM.contextMenuTitle)
            }
        }
    }
}
