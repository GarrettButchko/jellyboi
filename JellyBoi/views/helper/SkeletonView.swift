//
//  SkeletonView.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 8/28/26.
//

import SwiftUI
import BaseColors
import Observation

/// Single shared animation driver preserved for compatibility.
/// Pulsing is driven universally via `TimelineView` with `skeletonPulse`
/// so all blocks, icons, and bubble backgrounds remain in absolute lockstep.
@Observable
@MainActor
final class SkeletonPulse {
    static let shared = SkeletonPulse()
    var isAnimating = true

    func start() {
        isAnimating = true
    }
}

private struct SkeletonPulseKey: EnvironmentKey {
    static let defaultValue = SkeletonPulse.shared
}

extension EnvironmentValues {
    /// The shared pulse driver for skeleton blocks.
    var skeletonPulse: SkeletonPulse {
        get { self[SkeletonPulseKey.self] }
        set { self[SkeletonPulseKey.self] = newValue }
    }
}

// MARK: - Universal Pulse Modifier

/// Applies a smooth, lockstep pulsing opacity animation across all skeleton elements
/// driven by a universal timeline clock.
struct SkeletonPulseModifier: ViewModifier {
    var minOpacity: Double = 0.06
    var maxOpacity: Double = 0.13

    func body(content: Content) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            // Universal sine wave period: 1.8 seconds (0.9s ease out, 0.9s ease in)
            let progress = (sin(time * (.pi / 0.9)) + 1.0) / 2.0
            let opacity = minOpacity + progress * (maxOpacity - minOpacity)

            content.opacity(opacity)
        }
    }
}

extension View {
    /// Pulses the view in lockstep with all other skeleton elements.
    func skeletonPulse(minOpacity: Double = 0.06, maxOpacity: Double = 0.13) -> some View {
        modifier(SkeletonPulseModifier(minOpacity: minOpacity, maxOpacity: maxOpacity))
    }
}

/// Wraps a piece of content and a skeleton placeholder, cross-fading from the
/// skeleton to the real content once `showsContent` flips true.
struct SkeletonZone<Content: View, Placeholder: View>: View {
    let showsContent: Bool
    let placeholder: () -> Placeholder
    let content: () -> Content

    init(
        showsContent: Bool,
        @ViewBuilder placeholder: @escaping () -> Placeholder,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.showsContent = showsContent
        self.placeholder = placeholder
        self.content = content
    }

    var body: some View {
        ZStack {
            if showsContent {
                content()
                    .transition(.opacity)
            } else {
                placeholder()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: showsContent)
        .transaction { transaction in
            // Prevent initial layout/geometry resolution from animating size changes while skeleton is showing
            if !showsContent {
                transaction.animation = nil
            }
        }
    }
}

// MARK: - Carousel skeleton

struct SkeletonCarousel: View {
    var body: some View {
        VStack(spacing: 12) {
            GeometryReader { geometry in
                let w = geometry.size.width
                let cardWidth = w > 0 ? w * 0.8 : 300
                let cardHeight = cardWidth * 9 / 16
                SkeletonBlock(cornerRadius: 20)
                    .frame(width: cardWidth, height: cardHeight)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .aspectRatio(16 / (9 * 0.8), contentMode: .fit)
            .frame(maxWidth: .infinity)
            .transaction { $0.animation = nil }

            HStack(spacing: 5) {
                SkeletonBlock(cornerRadius: 3)
                    .frame(width: 20, height: 6)
                SkeletonBlock(cornerRadius: 3)
                    .frame(width: 6, height: 6)
                SkeletonBlock(cornerRadius: 3)
                    .frame(width: 6, height: 6)
                SkeletonBlock(cornerRadius: 3)
                    .frame(width: 6, height: 6)
                SkeletonBlock(cornerRadius: 3)
                    .frame(width: 6, height: 6)
                SkeletonBlock(cornerRadius: 3)
                    .frame(width: 6, height: 6)
            }
        }
    }
}

// MARK: - Stats skeleton

struct SkeletonStatsRow: View {
    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                statBubble(icon: "film", valueWidth: 36, labelWidth: 46)
                doubleStatBubble(
                    leftIcon: "tv", leftValueWidth: 32, leftLabelWidth: 42,
                    rightIcon: "film.stack", rightValueWidth: 38, rightLabelWidth: 54
                )
                statBubble(icon: "play.circle", valueWidth: 28, labelWidth: 54)
                statBubble(icon: "heart.fill", valueWidth: 28, labelWidth: 52)
                statBubble(icon: "checkmark.circle.fill", valueWidth: 34, labelWidth: 62)
                statBubble(icon: "clock.fill", valueWidth: 30, labelWidth: 70)
            }
            .padding(.horizontal, 16)
        }
        .scrollIndicators(.hidden)
        .disabled(true)
    }

    private func statBubble(icon: String, valueWidth: CGFloat, labelWidth: CGFloat) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.mainOpp)
                .frame(width: 24)
                .skeletonPulse(minOpacity: 0.18, maxOpacity: 0.45)

            VStack(alignment: .leading, spacing: 6) {
                SkeletonBlock(cornerRadius: 4)
                    .frame(width: valueWidth, height: 16)
                SkeletonBlock(cornerRadius: 4)
                    .frame(width: labelWidth, height: 10)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 56)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.mainOpp)
                .skeletonPulse(minOpacity: 0.04, maxOpacity: 0.09)
        )
    }

    private func doubleStatBubble(
        leftIcon: String, leftValueWidth: CGFloat, leftLabelWidth: CGFloat,
        rightIcon: String, rightValueWidth: CGFloat, rightLabelWidth: CGFloat
    ) -> some View {
        HStack(spacing: 0) {
            statBubbleHalf(icon: leftIcon, valueWidth: leftValueWidth, labelWidth: leftLabelWidth)

            Rectangle()
                .fill(Color.subTwo)
                .frame(width: 0.5)
                .padding(.vertical, 14)
                .skeletonPulse(minOpacity: 0.20, maxOpacity: 0.50)

            statBubbleHalf(icon: rightIcon, valueWidth: rightValueWidth, labelWidth: rightLabelWidth)
        }
        .frame(height: 56)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.mainOpp)
                .skeletonPulse(minOpacity: 0.04, maxOpacity: 0.09)
        )
    }

    private func statBubbleHalf(icon: String, valueWidth: CGFloat, labelWidth: CGFloat) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.mainOpp)
                .frame(width: 24)
                .skeletonPulse(minOpacity: 0.18, maxOpacity: 0.45)

            VStack(alignment: .leading, spacing: 6) {
                SkeletonBlock(cornerRadius: 4)
                    .frame(width: valueWidth, height: 16)
                SkeletonBlock(cornerRadius: 4)
                    .frame(width: labelWidth, height: 10)
            }
        }
        .padding(.horizontal, 14)
    }
}

// MARK: - Section row skeleton

struct SkeletonSectionRow: View {
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var cardWidth: CGFloat { sizeClass == .regular ? 160 : 110 }
    private var cardHeight: CGFloat { cardWidth * 1.5 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SkeletonBlock(cornerRadius: 6)
                .frame(width: 160, height: 22)
                .padding(.horizontal, 16)

            ScrollView(.horizontal) {
                HStack(spacing: 16) {
                    ForEach(0..<8, id: \.self) { _ in
                        SkeletonBlock(cornerRadius: 16)
                            .frame(width: cardWidth, height: cardHeight)
                    }
                }
                .padding(.horizontal, 16)
            }
            .scrollIndicators(.hidden)
            .disabled(true)
        }
    }
}

// MARK: - Media grid skeleton

/// Loading placeholder that mirrors `MediaView`'s adaptive grid of poster cards.
struct SkeletonMediaGrid: View {
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var minWidth: CGFloat { sizeClass == .regular ? 160 : 110 }
    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: minWidth), spacing: 16)]
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(0..<18, id: \.self) { _ in
                SkeletonBlock(cornerRadius: 16)
                    .aspectRatio(2/3, contentMode: .fill)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
}

// MARK: - Episodes row skeleton

/// Loading placeholder for the horizontal scrolling episodes row.
struct SkeletonEpisodesRow: View {
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var cardHeight: CGFloat { sizeClass == .regular ? 140 : 120 }
    private var cardWidth: CGFloat { cardHeight * (16.0 / 9.0) }

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(0..<5, id: \.self) { _ in
                    SkeletonBlock(cornerRadius: 16)
                        .frame(width: cardWidth, height: cardHeight)
                }
            }
            .padding(.horizontal, 16)
        }
        .scrollClipDisabled()
        .scrollIndicators(.hidden)
        .disabled(true)
    }
}

// MARK: - Episodes section skeleton

/// Loading placeholder that mirrors the episodes section of a series detail view.
struct SkeletonEpisodesSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SkeletonBlock(cornerRadius: 6)
                .frame(width: 100, height: 22)
                .padding(.horizontal, 16)

            SkeletonEpisodesRow()
        }
    }
}

// MARK: - Detail content skeleton

/// Loading placeholder that mirrors the content area of `MediaDetailView`
/// (overview, info chips, episodes row if series, cast row, and similar-items row).
struct SkeletonDetailContent: View {
    var isSeries: Bool = false
    var isCollection: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Overview
            VStack(alignment: .leading, spacing: 8) {
                SkeletonBlock(cornerRadius: 4).frame(maxWidth: .infinity).frame(height: 14)
                SkeletonBlock(cornerRadius: 4).frame(maxWidth: .infinity).frame(height: 14)
                SkeletonBlock(cornerRadius: 4).frame(height: 14).frame(maxWidth: .infinity, alignment: .leading).padding(.trailing, 80)
            }
            .padding(.horizontal, 20)

            // Info chips
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach([70, 90, 50, 80, 60] as [CGFloat], id: \.self) { w in
                        SkeletonBlock(cornerRadius: 14).frame(width: w, height: 32)
                    }
                }
                .padding(.horizontal, 20)
            }
            .scrollIndicators(.hidden)
            .disabled(true)

            // Episodes bar skeleton (if series)
            if isSeries {
                SkeletonEpisodesSection()
            }

            if isCollection {
                // Collection items grid skeleton
                VStack(alignment: .leading, spacing: 12) {
                    SkeletonBlock(cornerRadius: 6)
                        .frame(width: 140, height: 22)
                        .padding(.horizontal, 16)

                    SkeletonMediaGrid()
                }
            } else {
                // Cast section
                VStack(alignment: .leading, spacing: 12) {
                    SkeletonBlock(cornerRadius: 6)
                        .frame(width: 110, height: 22)
                        .padding(.horizontal, 16)

                    ScrollView(.horizontal) {
                        HStack(alignment: .top, spacing: 16) {
                            ForEach(0..<8, id: \.self) { _ in
                                VStack(spacing: 7) {
                                    SkeletonBlock(cornerRadius: 35).frame(width: 70, height: 70)
                                    SkeletonBlock(cornerRadius: 4).frame(width: 60, height: 10)
                                    SkeletonBlock(cornerRadius: 4).frame(width: 45, height: 9)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .scrollIndicators(.hidden)
                    .disabled(true)
                }

                // More Like This
                SkeletonSectionRow()
            }
        }
        .padding(.top, 16)
        .padding(.bottom, 48)
    }
}

// MARK: - Animated block

struct SkeletonBlock: View {
    let cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.mainOpp)
            .skeletonPulse(minOpacity: 0.06, maxOpacity: 0.13)
    }
}

#Preview {
    ZStack {
        Color.bg.ignoresSafeArea()
        VStack(alignment: .leading, spacing: 28) {
            SkeletonCarousel()
            SkeletonStatsRow()
            SkeletonSectionRow()
            SkeletonSectionRow()
        }
        .padding(.top, 24)
    }
}
