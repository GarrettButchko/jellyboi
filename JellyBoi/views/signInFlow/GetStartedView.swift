//
//  GetStartedView.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 8/19/26.
//

import SwiftUI
import SDWebImageSwiftUI
import StatusOverlayKit

struct GetStartedView: View {

    @EnvironmentObject var viewManager: ViewManager

    var body: some View {
        ZStack {
            AnimatedGradientBackground()

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 16) {
                    AnimatedImage(name: "floatingJellyWhite.gif")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 140, height: 140)
                        .clipShape(RoundedRectangle(cornerRadius: 24))

                    VStack(spacing: 3) {
                        Text("Jellyboi")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)

                        Text("A Jellyfin Client")
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.70))
                    }
                }

                Spacer()

                VStack(spacing: 7) {
                    Text("Stream your media, your way.")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.60))

                    Button {
                        viewManager.startSignIn()
                    } label: {
                        Text("Get Started")
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            
                    }
                    .glassEffect(
                        .clear.interactive(),
                        in: RoundedRectangle(cornerRadius: 16)
                    )
                    .foregroundStyle(Color.white)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 52)
            }
        }
        .ignoresSafeArea()
        .consumesTransientStatus()
    }
}
