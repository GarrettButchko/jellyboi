//
//  JellyBoiLoadingIndicator.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 11/6/26.
//

import SwiftUI
import BaseColors
import SDWebImageSwiftUI
import StatusOverlayKit

struct JellyBoiLoadingIndicator: View {
    @Environment(\.colorScheme) private var colorScheme

    var size: CGFloat = 56

    var body: some View {
        AnimatedImage(name: colorScheme == .light ? "jellyFishAniBlack.gif" : "jellyFishAniWhite.gif", bundle: .main)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .opacity(0.6)
            .rotationEffect(Angle(degrees: 45))
    }
}
