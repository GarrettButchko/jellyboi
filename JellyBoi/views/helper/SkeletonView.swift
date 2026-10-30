//
//  SkeletonView.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 8/28/26.
//

import SwiftUI
import BaseColors

// MARK: - Skeleton Primitives

/// The foundational static placeholder shape used across all skeleton components.
struct SkeletonBlock: View {
    let cornerRadius: CGFloat

    init(cornerRadius: CGFloat = 8) {
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.mainOpp.opacity(0.08))
    }
}

/// Swaps between a static placeholder block and actual content with a smooth fade animation.
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
            if !showsContent {
                transaction.animation = nil
            }
        }
    }
}

// MARK: - Home View Skeletons

/// Static placeholder that mirrors the hero carousel on `HomeView`.
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

/// Static placeholder that mirrors the statistics bubble row on `HomeView`.
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
        statBubbleHalf(icon: icon, valueWidth: valueWidth, labelWidth: labelWidth)
            .padding(.horizontal, 14)
            .frame(height: 56)
            .background(Color.mainOpp.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func doubleStatBubble(
        leftIcon: String, leftValueWidth: CGFloat, leftLabelWidth: CGFloat,
        rightIcon: String, rightValueWidth: CGFloat, rightLabelWidth: CGFloat
    ) -> some View {
        HStack(spacing: 0) {
            statBubbleHalf(icon: leftIcon, valueWidth: leftValueWidth, labelWidth: leftLabelWidth)
                .padding(.horizontal, 14)

            Rectangle()
                .fill(Color.subTwo)
                .frame(width: 0.5)
                .padding(.vertical, 14)

            statBubbleHalf(icon: rightIcon, valueWidth: rightValueWidth, labelWidth: rightLabelWidth)
                .padding(.horizontal, 14)
        }
        .frame(height: 56)
        .background(Color.mainOpp.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func statBubbleHalf(icon: String, valueWidth: CGFloat, labelWidth: CGFloat) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.mainOpp.opacity(0.45))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                SkeletonBlock(cornerRadius: 4)
                    .frame(width: valueWidth, height: 16)
                SkeletonBlock(cornerRadius: 4)
                    .frame(width: labelWidth, height: 10)
            }
        }
    }
}

/// Static placeholder that mirrors a horizontal media shelf (`SectionRow`).
struct SkeletonSectionRow: View {
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var cardWidth: CGFloat { sizeClass == .regular ? 160 : 110 }
    private var cardHeight: CGFloat { cardWidth * 1.5 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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

// MARK: - Media & Grid Skeletons

/// Static placeholder that mirrors `MediaView`'s adaptive grid of poster cards.
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

// MARK: - Detail View Skeletons

/// Static placeholder for the horizontal scrolling episodes row.
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

/// Static placeholder that mirrors the episodes section of a series detail view.
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

/// Static placeholder that mirrors the special features section of a detail view.
struct SkeletonSpecialFeaturesSection: View {
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var cardHeight: CGFloat { sizeClass == .regular ? 140 : 110 }
    private var cardWidth: CGFloat { cardHeight * (16.0 / 9.0) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SkeletonBlock(cornerRadius: 6)
                .frame(width: 140, height: 22)
                .padding(.horizontal, 16)

            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(0..<4, id: \.self) { _ in
                        VStack(alignment: .leading, spacing: 6) {
                            SkeletonBlock(cornerRadius: 16)
                                .frame(width: cardWidth, height: cardHeight)

                            SkeletonBlock(cornerRadius: 4)
                                .frame(width: cardWidth * 0.7, height: 12)

                            SkeletonBlock(cornerRadius: 4)
                                .frame(width: cardWidth * 0.35, height: 10)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            .scrollClipDisabled()
            .scrollIndicators(.hidden)
            .disabled(true)
        }
    }
}

/// Static placeholder that mirrors the content area of `MediaDetailView`
/// (overview, info chips, episodes row if series, cast row, and similar-items row).
struct SkeletonDetailContent: View {
    var isSeries: Bool = false
    var isCollection: Bool = false
    var hasSpecialFeatures: Bool = false

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

                if hasSpecialFeatures {
                    // Special Features section skeleton
                    SkeletonSpecialFeaturesSection()
                }

                // More Like This
                SkeletonSectionRow()
            }
        }
        .padding(.top, 16)
        .padding(.bottom, 48)
    }
}

// MARK: - Preview

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
