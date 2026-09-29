//
//  HomeSkeletonView.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 8/28/26.
//

import SwiftUI
import BaseColors
import Observation

/// Single shared animation driver so every skeleton block pulses in lockstep
/// and appears at exactly the same time, regardless of when it was created.
@Observable
@MainActor
final class SkeletonPulse {
    static let shared = SkeletonPulse()
    var isAnimating = false

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

/// Wraps a piece of content and a skeleton placeholder, cross-fading from the
/// skeleton to the real content once `showsContent` flips true.
struct SkeletonZone<Content: View, Placeholder: View>: View {
    let showsContent: Bool
    let placeholder: Placeholder
    let content: Content

    init(
        showsContent: Bool,
        @ViewBuilder placeholder: () -> Placeholder,
        @ViewBuilder content: () -> Content
    ) {
        self.showsContent = showsContent
        self.placeholder = placeholder()
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsContent {
                content
                    .transition(.opacity)
            } else {
                placeholder
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: showsContent)
    }
}

// MARK: - Carousel skeleton

struct SkeletonCarousel: View {
    @Environment(\.skeletonPulse) private var pulse

    var body: some View {
        VStack(spacing: 12) {
            GeometryReader { geometry in
                let cardWidth = geometry.size.width * 0.8
                let cardHeight = cardWidth * 9 / 16
                SkeletonBlock(cornerRadius: 20)
                    .frame(width: cardWidth, height: cardHeight)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .aspectRatio(16 / (9 * 0.8), contentMode: .fit)
            .frame(maxWidth: .infinity)

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
        .onAppear { pulse.start() }
    }
}

// MARK: - Stats skeleton

struct SkeletonStatsRow: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.skeletonPulse) private var pulse

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                statBubble
                doubleStatBubble
                statBubble
                statBubble
                statBubble
                statBubble
            }
            .padding(.horizontal, 16)
        }
        .scrollIndicators(.hidden)
        .disabled(true)
        .onAppear { pulse.start() }
    }

    private var statBubble: some View {
        HStack(spacing: 10) {
            SkeletonBlock(cornerRadius: 8)
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 6) {
                SkeletonBlock(cornerRadius: 4)
                    .frame(width: 40, height: 16)
                SkeletonBlock(cornerRadius: 4)
                    .frame(width: 56, height: 10)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 56)
        .background(Color.mainOpp.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var doubleStatBubble: some View {
        HStack(spacing: 0) {
            statBubblePair
            Rectangle()
                .fill(Color.mainOpp.opacity(0.15))
                .frame(width: 0.5)
                .padding(.vertical, 14)
            statBubblePair
        }
        .frame(height: 56)
        .background(Color.mainOpp.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var statBubblePair: some View {
        HStack(spacing: 10) {
            SkeletonBlock(cornerRadius: 8)
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 6) {
                SkeletonBlock(cornerRadius: 4)
                    .frame(width: 40, height: 16)
                SkeletonBlock(cornerRadius: 4)
                    .frame(width: 46, height: 10)
            }
        }
        .padding(.horizontal, 14)
    }
}

// MARK: - Section row skeleton

struct SkeletonSectionRow: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.skeletonPulse) private var pulse

    private var cardWidth: CGFloat { sizeClass == .regular ? 160 : 110 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SkeletonBlock(cornerRadius: 6)
                .frame(width: 160, height: 22)
                .padding(.horizontal, 16)

            ScrollView(.horizontal) {
                LazyHStack(spacing: 16) {
                    ForEach(0..<8, id: \.self) { _ in
                        SkeletonBlock(cornerRadius: 16)
                            .aspectRatio(2/3, contentMode: .fit)
                            .frame(width: cardWidth)
                    }
                }
                .padding(.horizontal, 16)
            }
            .scrollIndicators(.hidden)
            .disabled(true)
        }
        .onAppear { pulse.start() }
    }
}

// MARK: - Media grid skeleton

/// Loading placeholder that mirrors `MediaView`'s adaptive grid of poster cards.
struct SkeletonMediaGrid: View {
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: sizeClass == .regular ? 160 : 110), spacing: 16)]
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(0..<18, id: \.self) { _ in
                SkeletonBlock(cornerRadius: 16)
                    .aspectRatio(2/3, contentMode: .fit)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
}

// MARK: - Episodes section skeleton

/// Loading placeholder that mirrors the episodes section of a series detail view.
struct SkeletonEpisodesSection: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.skeletonPulse) private var pulse

    private var cardHeight: CGFloat { sizeClass == .regular ? 140 : 120 }
    private var cardWidth: CGFloat { cardHeight * (16.0 / 9.0) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SkeletonBlock(cornerRadius: 6)
                .frame(width: 100, height: 22)
                .padding(.horizontal, 16)

            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(0..<5, id: \.self) { _ in
                        SkeletonBlock(cornerRadius: 16)
                            .frame(width: cardWidth, height: cardHeight)
                    }
                }
                .padding(.horizontal, 16)
            }
            .scrollIndicators(.hidden)
            .disabled(true)
        }
        .onAppear { pulse.start() }
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
        .onAppear { SkeletonPulse.shared.start() }
    }
}

// MARK: - Animated block

struct SkeletonBlock: View {
    let cornerRadius: CGFloat

    @Environment(\.skeletonPulse) private var pulse

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.mainOpp.opacity(pulse.isAnimating ? 0.06 : 0.12))
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse.isAnimating)
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
