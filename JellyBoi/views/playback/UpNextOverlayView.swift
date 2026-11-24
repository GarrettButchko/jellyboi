//
//  UpNextOverlayView.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 10/27/26.
//

import SwiftUI
import JellyfinAPI
import BaseColors

struct UpNextOverlayView: View {
    var nextItem: BaseItemDto? = nil
    let secondsRemaining: Int
    var progressFraction: Double = 0.0
    var areControlsVisible: Bool = true
    let onPlayNow: () -> Void
    var onDismiss: (() -> Void)? = nil

    init(
        nextItem: BaseItemDto? = nil,
        state: PlayerViewModel.UpNextState,
        areControlsVisible: Bool = true,
        onPlayNow: @escaping () -> Void,
        onDismiss: (() -> Void)? = nil
    ) {
        self.nextItem = nextItem
        self.secondsRemaining = state.secondsRemaining
        self.progressFraction = state.progressFraction
        self.areControlsVisible = areControlsVisible
        self.onPlayNow = onPlayNow
        self.onDismiss = onDismiss
    }

    init(
        nextItem: BaseItemDto? = nil,
        secondsRemaining: Int,
        progressFraction: Double = 0.0,
        areControlsVisible: Bool = true,
        onPlayNow: @escaping () -> Void,
        onDismiss: (() -> Void)? = nil
    ) {
        self.nextItem = nextItem
        self.secondsRemaining = secondsRemaining
        self.progressFraction = progressFraction
        self.areControlsVisible = areControlsVisible
        self.onPlayNow = onPlayNow
        self.onDismiss = onDismiss
    }

    private var effectiveProgressFraction: Double {
        if progressFraction > 0.0 {
            return progressFraction
        }
        let clamped = max(0, min(30, Double(secondsRemaining)))
        return (30.0 - clamped) / 30.0
    }

    var body: some View {
        VStack {
            Spacer()
            HStack(spacing: 10) {
                Spacer()

                // "Play Next" button with left-to-right filling progress
                Button(action: onPlayNow) {
                    buttonLabel(isFilled: false)
                        .background(Color.black.opacity(0.6))
                        .overlay {
                            GeometryReader { geo in
                                buttonLabel(isFilled: true)
                                    .background(Color.white)
                                    .frame(width: geo.size.width, height: geo.size.height)
                                    .mask(alignment: .leading) {
                                        Rectangle()
                                            .frame(width: geo.size.width * effectiveProgressFraction)
                                    }
                            }
                        }
                        .playerGlass(in: Capsule())
                }
                .buttonStyle(.plain)
                .animation(.linear(duration: 0.25), value: effectiveProgressFraction)
            }
            .padding(.trailing, 24)
            .padding(.bottom, areControlsVisible ? 115 : 24)
            .animation(.easeInOut(duration: 0.25), value: areControlsVisible)
        }
        .safeAreaPadding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .environment(\.colorScheme, .dark)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func buttonLabel(isFilled: Bool) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "forward.fill")
                .font(.system(size: 11, weight: .bold))
                .contentTransition(.symbolEffect(.replace))
            Text("Play Next")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .fixedSize()
        }
        .foregroundStyle(isFilled ? Color.black : Color.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
