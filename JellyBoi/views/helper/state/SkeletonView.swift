//
//  SkeletonView.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 8/28/26.
//

import SwiftUI
import BaseColors
import JellyfinAPI

// MARK: - Skeleton Animation

public extension Animation {
    /// The global animation used for skeleton transitions throughout the app.
    static let skeleton: Animation = .easeInOut(duration: 0.35)
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

// MARK: - Animated Skeleton Modifier

/// Applies the skeleton placeholder and owns the animation for its content.
///
/// Every time `value` changes the whole subtree (including the section title) transitions
/// using `Animation.skeleton`, so call sites no longer need to pair `.animation(.skeleton, value:)`
/// with a `.transition(.skeleton)` on each loading branch.
public struct AnimatedSkeletonModifier<Value: Equatable>: ViewModifier {
    let isActive: Bool
    let value: Value

    public init(
        isActive: Bool = true,
        value: Value
    ) {
        self.isActive = isActive
        self.value = value
    }

    public func body(content: Content) -> some View {
        content
            .modifier(SkeletonModifier(isActive: isActive))
            .animation(.skeleton, value: value)
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

    /// Masks the view into a static skeleton placeholder while `isLoading` is true and drives
    /// the fade between the placeholder and the loaded content off `value`, so a single
    /// modifier handles both the skeleton state and its animation.
    func skeleton<V: Equatable>(
        when isLoading: Bool,
        value: V
    ) -> some View {
        modifier(AnimatedSkeletonModifier(isActive: isLoading, value: value))
    }

    /// Masks the view into a static skeleton placeholder while `isActive` is true and drives
    /// the fade between the placeholder and the loaded content off `value`.
    func skeleton<V: Equatable>(
        isActive: Bool = true,
        value: V
    ) -> some View {
        modifier(AnimatedSkeletonModifier(isActive: isActive, value: value))
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

private let previewSkeletonItems: [BaseItemDto] = (0..<6).map { index in
    BaseItemDto(
        id: "preview-skeleton-\(index)",
        name: "Preview Movie",
        type: .movie
    )
}

#Preview {
    ZStack {
        Color.bg.ignoresSafeArea()
        VStack(alignment: .leading, spacing: 20) {
            SkeletonBlock(cornerRadius: 12)
                .frame(height: 180)
                .padding(.horizontal, 16)

            SectionRow(
                title: "Popular Movies",
                items: previewSkeletonItems
            )
            .skeleton()
        }
    }
}
