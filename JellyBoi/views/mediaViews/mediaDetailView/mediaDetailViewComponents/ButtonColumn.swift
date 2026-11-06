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
            if detailVM.shouldShowOptionsButton {
                let isOptionsDisabled = detailVM.isOptionsDisabled
                Button {
                    showOptionsSheet = true
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.mainOpp.opacity(isOptionsDisabled ? 0.35 : 1.0))
                        .frame(width: 50, height: 50)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(isOptionsDisabled)
                .glassEffect(.regular.interactive(), in: Circle())
                .animation(.smooth(duration: 0.25), value: isOptionsDisabled)
            }

            GlassEffectContainer(spacing: 8) {
                VStack(spacing: 8) {
                    if detailVM.progressVisible {
                        progressRingButton
                            .glassEffect(.regular.tint(.mainOpp.opacity(0.9)).interactive())
                            .glassEffectUnion(id: "colBut", namespace: glassNamespace)
                            .transition(.scale(scale: 0.8).combined(with: .opacity))
                    }
                    let isPlayDisabled = detailVM.isPlayDisabled || playbackManager.isLoading
                    Button {
                        detailVM.handlePlayTap(
                            playbackManager: playbackManager,
                            serverViewModel: serverViewModel,
                            libraryViewModel: libraryViewModel
                        )
                    } label: {
                        Image(systemName: "play.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.main.opacity(isPlayDisabled ? 0.35 : 1.0))
                            .frame(width: 50, height: 50)
                    }
                    .buttonStyle(.plain)
                    .disabled(isPlayDisabled)
                    .glassEffect(.regular.tint(.mainOpp.opacity(0.9)).interactive())
                    .glassEffectUnion(id: "colBut", namespace: glassNamespace)
                    .contentShape(.contextMenuPreview, Circle())
                    .contextMenu {
                        playbackMenuContent
                    }
                    .animation(.smooth(duration: 0.25), value: isPlayDisabled)
                }
            }
        }
        .animation(.smooth(duration: 0.3), value: detailVM.progressVisible)
    }

    // MARK: - Progress Ring Button

    private var progressRingButton: some View {
        let accent = preferences?.accentColor ?? Color.appAccent
        return Menu {
            playbackMenuContent
        } label: {
            ZStack {
                Circle()
                    .stroke(Color.main.opacity(0.1), lineWidth: 5)
                    .frame(width: 35, height: 35)

                if detailVM.isWatched {
                    Circle()
                        .stroke(accent, lineWidth: 5)
                        .frame(width: 35, height: 35)

                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.main)
                } else {
                    Circle()
                        .trim(from: 0, to: detailVM.progressValue)
                        .stroke(accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 35, height: 35)

                    Text(detailVM.percentText)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.main)
                }
            }
            .frame(width: 50, height: 50)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Playback Menu Content

    @ViewBuilder
    private var playbackMenuContent: some View {
        let isSeriesContainer = detailVM.displayItem?.type == .series
        PlaybackMenuContent(
            title: !isSeriesContainer ? detailVM.targetPlayableTitle() : nil,
            isInProgress: detailVM.isInProgress,
            isWatched: detailVM.isWatched,
            onContinueWatching: {
                detailVM.playMedia(
                    fromBeginning: false,
                    playbackManager: playbackManager,
                    serverViewModel: serverViewModel,
                    libraryViewModel: libraryViewModel
                )
            },
            onStartFromBeginning: {
                if isSeriesContainer {
                    detailVM.seriesAlertAction = .startFromBeginning
                } else {
                    detailVM.playMedia(
                        fromBeginning: true,
                        playbackManager: playbackManager,
                        serverViewModel: serverViewModel,
                        libraryViewModel: libraryViewModel
                    )
                }
            },
            onStart: {
                detailVM.playMedia(
                    fromBeginning: false,
                    playbackManager: playbackManager,
                    serverViewModel: serverViewModel,
                    libraryViewModel: libraryViewModel
                )
            },
            onResetProgress: {
                if isSeriesContainer {
                    detailVM.seriesAlertAction = .resetProgress
                } else {
                    detailVM.resetProgress(serverViewModel: serverViewModel)
                }
            }
        )
    }
}
