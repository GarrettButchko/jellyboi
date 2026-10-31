//
//  SkeletonView.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 8/28/26.
//

import SwiftUI
import BaseColors

// MARK: - Skeleton Modifier

public struct SkeletonModifier: ViewModifier {
    let isActive: Bool

    public func body(content: Content) -> some View {
        if isActive {
            content
                .redacted(reason: .placeholder)
                .disabled(true)
                .transaction { $0.animation = nil }
        } else {
            content
        }
    }
}

public extension View {
    /// Masks the view into a static skeleton placeholder matching its exact shape and layout.
    func skeleton(isActive: Bool = true) -> some View {
        modifier(SkeletonModifier(isActive: isActive))
    }
}

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
        .padding(.top, 24)
    }
}
