//
//  PlayerGlassModifier.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 11/22/26.
//

import SwiftUI

/// Collective Liquid Glass styling modifier for all player controls and next-play buttons.
struct PlayerGlassModifier<S: Shape>: ViewModifier {
    var shape: S
    var isInteractive: Bool = true
    var backgroundDimming: Double = 0.35

    func body(content: Content) -> some View {
        let style = Glass.clear
            .tint(Color.black.opacity(backgroundDimming))

        content
            .glassEffect(isInteractive ? style.interactive() : style, in: shape)
    }
}

extension View {
    func playerGlass<S: Shape>(
        in shape: S,
        isInteractive: Bool = true,
        backgroundDimming: Double = 0.35
    ) -> some View {
        modifier(PlayerGlassModifier(
            shape: shape,
            isInteractive: isInteractive,
            backgroundDimming: backgroundDimming
        ))
    }
}
