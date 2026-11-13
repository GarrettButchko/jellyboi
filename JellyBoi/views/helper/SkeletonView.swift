//
//  SkeletonView.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 8/28/26.
//

import SwiftUI
import BaseColors

// MARK: - Skeleton Animation

public extension Animation {
    /// The global animation used for skeleton transitions throughout the app.
    static let skeleton: Animation = .easeInOut(duration: 0.2)
    /// The global animation used for skeleton transitions throughout the app.
    static let skeletonTransition: Animation = .skeleton
}

public extension AnyTransition {
    /// The global transition used for skeleton content fading in or out.
    static var skeleton: AnyTransition {
        .opacity.animation(.skeleton)
    }
}

// MARK: - Skeleton Modifier

public struct SkeletonModifier: ViewModifier {
    let isActive: Bool

    public init(
        isActive: Bool = true
    ) {
        self.isActive = isActive
    }

    public func body(content: Content) -> some View {
        content
            .redacted(reason: isActive ? .placeholder : [])
            .disabled(isActive)
            .transaction { transaction in
                if isActive {
                    // Skeletons remain completely static while active (no continuous shimmer or pulsing)
                    transaction.animation = nil
                }
            }
    }
}

public extension View {
    /// Masks the view into a static skeleton placeholder while `isLoading` is true,
    /// smoothly animating in when `isLoading` becomes false.
    func skeleton(
        when isLoading: Bool
    ) -> some View {
        modifier(SkeletonModifier(isActive: isLoading))
    }

    /// Masks the view into a static skeleton placeholder while `isActive` is true,
    /// smoothly animating in when `isActive` becomes false.
    func skeleton(
        isActive: Bool = true
    ) -> some View {
        modifier(SkeletonModifier(isActive: isActive))
    }
}

// MARK: - Skeleton Primitives

public struct SkeletonBlock: View {
    let cornerRadius: CGFloat

    public init(cornerRadius: CGFloat = 8) {
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.mainOpp.opacity(0.08))
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
                items: .placeholders
            )
            .skeleton()
        }
    }
}
