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
    @State private var showLetsConnect = false
    @State private var pendingServerSignIn = false

    var body: some View {
        ZStack {
            AnimatedGradientBackground()

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 16) {
                    AnimatedImage(name: "jellyFishAniWhite.gif")
                        .resizable()
                        .rotationEffect(Angle(degrees: 45))
                        .scaledToFit()
                        .frame(width: 120, height: 120)
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
                        showLetsConnect = true
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
        .sheet(isPresented: $showLetsConnect, onDismiss: {
            if pendingServerSignIn {
                pendingServerSignIn = false
                viewManager.navigateToServerSignIn()
            }
        }) {
            LetsConnectView(onConnected: { pendingServerSignIn = true })
        }
    }
}



#Preview {
    GetStartedView()
        .environmentObject(ViewManager())
}
