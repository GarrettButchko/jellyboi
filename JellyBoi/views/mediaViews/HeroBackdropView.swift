//
//  HeroBackdropView.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 9/9/26.
//

import SwiftUI
import SDWebImageSwiftUI

/// A full-bleed, blurred backdrop image with top-to-bottom gradient fading.
/// Shared between the carousel background in `HomeView` and the hero background in `MediaDetailView`.
struct HeroBackdropView: View {
    let url: URL?
    var itemID: String? = nil
    var height: CGFloat = 1150
    var blurRadius: CGFloat = 40
    var isFlipped: Bool = false
    var gradientColors: [Color] = [.black, .black.opacity(0.5), .clear]

    var body: some View {
        if let url {
            WebImage(
                url: url,
                transaction: Transaction(animation: .easeInOut(duration: 0.4))
            ) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .scaledToFill()
                        .scaleEffect(x: isFlipped ? -1 : 1, y: 1)
                        .transition(.fade(duration: 0.4))
                } else {
                    Color.clear
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .blur(radius: blurRadius)
            .mask(
                LinearGradient(
                    colors: gradientColors,
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .ignoresSafeArea(edges: .top)
            .id(itemID ?? url.absoluteString)
            .animation(.easeInOut(duration: 0.35), value: itemID ?? url.absoluteString)
        } else {
            Color.clear
        }
    }
}
