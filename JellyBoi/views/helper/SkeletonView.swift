//
//  SkeletonView.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 8/28/26.
//

import SwiftUI
import BaseColors
@_exported import SkeletonKit

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
        .animation(.easeInOut(duration: 0.35), value: showsContent)
        .transaction { transaction in
            if !showsContent {
                transaction.animation = nil
            }
        }
    }
}

// MARK: - Backward Compatibility Extension

public extension View {
    /// Masks the view into a static skeleton placeholder while `isActive` is true,
    /// smoothly animating in when `isActive` becomes false.
    func skeleton(isActive: Bool = true) -> some View {
        self.skeleton(when: isActive)
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.bg.ignoresSafeArea()
        VStack(alignment: .leading, spacing: 20) {
            SkeletonBlock(cornerRadius: 12)
                .frame(height: 180)
                .padding(.horizontal, 16)

            SectionRow(
                title: "Popular Movies",
                items: .placeholders(count: 6)
            )
            .skeleton()
        }
    }
}
