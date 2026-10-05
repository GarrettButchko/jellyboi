//
//  PlayProgressPill.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 8/25/26.
//

import SwiftUI
import BaseColors
import JellyfinAPI

struct MediaButtonColumn: View {

    let item: BaseItemDto
    var onOptions: (() -> Void)? = nil
    var onPlay: (() -> Void)? = nil
    var onContinueWatching: (() -> Void)? = nil
    var onStartFromBeginning: (() -> Void)? = nil
    var onResetProgress: (() -> Void)? = nil

    @Namespace private var glassNamespace
    @Environment(ServerViewModel.self) private var serverViewModel: ServerViewModel?

    @State private var viewModel: MediaButtonColumnViewModel

    init(
        item: BaseItemDto,
        onOptions: (() -> Void)? = nil,
        onPlay: (() -> Void)? = nil,
        onContinueWatching: (() -> Void)? = nil,
        onStartFromBeginning: (() -> Void)? = nil,
        onResetProgress: (() -> Void)? = nil
    ) {
        self.item = item
        self.onOptions = onOptions
        self.onPlay = onPlay
        self.onContinueWatching = onContinueWatching
        self.onStartFromBeginning = onStartFromBeginning
        self.onResetProgress = onResetProgress
        _viewModel = State(initialValue: MediaButtonColumnViewModel(item: item))
    }

    var body: some View {
        VStack(spacing: 12) {
            if viewModel.shouldShowOptions(hasOptionsCallback: onOptions != nil), let onOptions {
                Button(action: onOptions) {
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
                    if viewModel.progressVisible {
                        progressRingButton
                            .glassEffect(.regular.tint(.mainOpp.opacity(0.9)).interactive())
                            .glassEffectUnion(id: "colBut", namespace: glassNamespace)
                            .transition(.opacity)
                    }
                    Button {
                        viewModel.handlePlayTap(
                            onPlay: onPlay,
                            onContinueWatching: onContinueWatching,
                            onStartFromBeginning: onStartFromBeginning
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
        .animation(.smooth, value: viewModel.progressVisible)
        .onChange(of: item) { _, newItem in
            viewModel.updateItem(newItem)
        }
        .onReceive(NotificationCenter.default.publisher(for: .mediaProgressReset)) { notification in
            if let resetID = notification.object as? String {
                viewModel.handleProgressResetNotification(resetID: resetID)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .mediaProgressUpdated)) { notification in
            if let updatedID = notification.object as? String,
               let ticks = notification.userInfo?["positionTicks"] as? Int {
                let total = notification.userInfo?["durationTicks"] as? Int
                viewModel.handleProgressUpdatedNotification(itemID: updatedID, positionTicks: ticks, totalTicks: total)
            }
        }
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

                if viewModel.isWatched {
                    Circle()
                        .stroke(Color.accent, lineWidth: 5)
                        .frame(width: 35, height: 35)

                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.main)
                } else {
                    Circle()
                        .trim(from: 0, to: viewModel.progressValue)
                        .stroke(Color.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 35, height: 35)

                    Text(viewModel.percentText)
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
            if viewModel.isInProgress {
                Button {
                    viewModel.handleContinueWatching(
                        onPlay: onPlay,
                        onContinueWatching: onContinueWatching
                    )
                } label: {
                    Label("Continue watching", systemImage: "play.fill")
                }

                Button {
                    viewModel.handleStartFromBeginning(
                        onStartFromBeginning: onStartFromBeginning
                    )
                } label: {
                    Label("Start from beginning", systemImage: "arrow.counterclockwise")
                }

                Button(role: .destructive) {
                    viewModel.handleResetProgress(
                        serverViewModel: serverViewModel,
                        onResetProgress: onResetProgress
                    )
                } label: {
                    Label("Reset Progress", systemImage: "xmark.circle")
                }
            } else if viewModel.isWatched {
                Button {
                    viewModel.handleStartFromBeginning(
                        onStartFromBeginning: onStartFromBeginning
                    )
                } label: {
                    Label("Start from beginning", systemImage: "arrow.counterclockwise")
                }

                Button(role: .destructive) {
                    viewModel.handleResetProgress(
                        serverViewModel: serverViewModel,
                        onResetProgress: onResetProgress
                    )
                } label: {
                    Label("Reset Progress", systemImage: "xmark.circle")
                }
            } else {
                Button {
                    viewModel.handleStart(
                        onPlay: onPlay,
                        onStartFromBeginning: onStartFromBeginning
                    )
                } label: {
                    Label("Start", systemImage: "play.fill")
                }
            }
        } header: {
            if !viewModel.contextMenuTitle.isEmpty {
                Text(viewModel.contextMenuTitle)
            }
        }
    }
}
