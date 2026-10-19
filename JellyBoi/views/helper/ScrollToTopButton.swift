//
//  ScrollToTopButton.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 8/27/26.
//

import SwiftUI

struct ScrollToTopButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 13, weight: .bold))
                Text("Top")
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// Floating overlay that sits over a scroll view and appears once the user
/// has scrolled past `threshold` points. Animates in from the bottom with
/// a blurReplace transition and passes taps through when hidden.
struct ScrollToTopOverlay: View {
    let isVisible: Bool
    var threshold: CGFloat = 300
    @Binding var STTButtonHeight: CGFloat
    let action: () -> Void

    init(
        scrollOffset: CGFloat,
        threshold: CGFloat = 300,
        STTButtonHeight: Binding<CGFloat>,
        action: @escaping () -> Void
    ) {
        self.isVisible = scrollOffset > threshold
        self.threshold = threshold
        self._STTButtonHeight = STTButtonHeight
        self.action = action
    }

    init(
        isVisible: Bool,
        threshold: CGFloat = 300,
        STTButtonHeight: Binding<CGFloat>,
        action: @escaping () -> Void
    ) {
        self.isVisible = isVisible
        self.threshold = threshold
        self._STTButtonHeight = STTButtonHeight
        self.action = action
    }

    var body: some View {
        ZStack {
            if isVisible {
                ScrollToTopButton(action: action)
                    .padding(.bottom, 8)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { STTButtonHeight = $0 }
                    .transition(.move(edge: .bottom).combined(with: .blurReplace))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .allowsHitTesting(isVisible)
        .animation(.smooth(duration: 0.3), value: isVisible)
    }
}
