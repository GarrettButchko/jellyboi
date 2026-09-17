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

    // MARK: - Nested Types

    enum PlaybackState: Equatable {
        case unwatched
        case inProgress(Double)   // 0.0 – 1.0
        case completed
    }

    // MARK: - Properties

    let item: BaseItemDto
    var onOptions: (() -> Void)? = nil
    @State private var state: PlaybackState
    @State private var progressVisible = false
    @Namespace private var glassNamespace

    static func playbackState(for item: BaseItemDto) -> PlaybackState {
        guard let pct = item.userData?.playedPercentage else { return .unwatched }
        if pct >= 100 {
            return .completed
        } else if pct > 0 {
            return .inProgress(pct / 100)
        } else {
            return .unwatched
        }
    }

    init(item: BaseItemDto, initialState: PlaybackState? = nil, onOptions: (() -> Void)? = nil) {
        self.onOptions = onOptions
        self.item = item
        _state = State(initialValue: initialState ?? Self.playbackState(for: item))
    }

    // MARK: - Computed helpers

    private var progressValue: Double {
        switch state {
        case .unwatched:         return 0
        case .inProgress(let p): return p
        case .completed:         return 1
        }
    }

    private var percentText: String {
        "\(Int(progressValue * 100))%"
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 12) {
            if let onOptions {
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

            GlassEffectContainer(spacing: 40) {
                VStack(spacing: 12) {
                    if progressVisible {
                        progressRingButton
                            .glassEffect(.regular.interactive(), in: Circle())
                            .glassEffectID("progress", in: glassNamespace)
                    }
                    Button {
                        handlePlayTap()
                    } label: {
                        Image(systemName: "play.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.main)
                            .frame(width: 50, height: 50)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.tint(.mainOpp.opacity(0.9)).interactive(), in: Circle())
                    .glassEffectID("play", in: glassNamespace)
                }
            }
        }
        .animation(.smooth, value: progressVisible)
        .onAppear {
            guard state != .unwatched else { return }
            withAnimation(.smooth.delay(0.4)) {
                progressVisible = true
            }
        }
        .onChange(of: state) { _, newValue in
            withAnimation(.smooth) {
                progressVisible = newValue != .unwatched
            }
        }
        .onChange(of: item.userData?.playedPercentage) { _, _ in
            state = Self.playbackState(for: item)
        }
    }

    // MARK: - Progress Ring Button

    private var progressRingButton: some View {
        Menu {
            Button("Continue watching") { }
            Button("Start from beginning") { }
            Button("Reset progress", role: .destructive) {
                withAnimation(.smooth) {
                    state = .unwatched
                }
            }
        } label: {
            ZStack {
                Circle()
                    .stroke(Color.mainOpp.opacity(0.1), lineWidth: 5)
                    .frame(width: 35, height: 35)

                Circle()
                    .trim(from: 0, to: progressValue)
                    .stroke(Color.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 35, height: 35)

                if state == .completed {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.mainOpp)
                } else {
                    Text(percentText)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.mainOpp)
                }
            }
            .frame(width: 50, height: 50)
        }
    }

    // MARK: - Interaction

    private func handlePlayTap() {
        switch state {
        case .unwatched:
            withAnimation(.smooth) {
                state = .inProgress(0.1)
            }
        case .inProgress:
            break
        case .completed:
            withAnimation(.smooth) {
                state = .inProgress(0.02)
            }
        }
    }
}

// MARK: - Previews

#Preview("Unwatched") {
    MediaButtonColumn(item: BaseItemDto(name: "Sample"), initialState: .unwatched)
        .padding(40)
}

#Preview("In Progress — 42%") {
    MediaButtonColumn(item: BaseItemDto(name: "Sample"), initialState: .inProgress(0.42))
        .padding(40)
}

#Preview("Completed") {
    MediaButtonColumn(item: BaseItemDto(name: "Sample"), initialState: .completed)
        .padding(40)
}
