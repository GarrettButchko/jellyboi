//
//  AnimatableAspectRatioModifier.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 9/9/26.
//

import SwiftUI

/// A view modifier that animates changes to aspect ratio smoothly over time
/// by interpolating `aspectRatio` on each frame rather than snapping to the new size.
struct AnimatableAspectRatioModifier: AnimatableModifier {
    var aspectRatio: CGFloat

    var animatableData: CGFloat {
        get { aspectRatio }
        set { aspectRatio = newValue }
    }

    func body(content: Content) -> some View {
        content
            .aspectRatio(max(aspectRatio, 0.01), contentMode: .fit)
    }
}

extension View {
    /// Constrains this view's dimensions to the specified aspect ratio with continuous animation support.
    func animatableAspectRatio(_ ratio: CGFloat) -> some View {
        modifier(AnimatableAspectRatioModifier(aspectRatio: ratio))
    }
}
