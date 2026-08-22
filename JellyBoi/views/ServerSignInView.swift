//
//  ServerSignInView.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 8/21/26.
//

import SwiftUI
import BaseColors
import StatusOverlayKit

struct ServerSignInView: View {
    @EnvironmentObject var viewManager: ViewManager

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.bg.ignoresSafeArea()

            Button {
                viewManager.navigateToGetStarted()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .padding(14)
            }
            .glassEffect(
                .regular.interactive(),
                in: Circle()
            )
            .foregroundStyle(Color.mainOpp)
            .padding(.top, 16)
            .padding(.leading, 20)
        }
        .consumesTransientStatus()
    }
}

#Preview {
    ServerSignInView()
}
