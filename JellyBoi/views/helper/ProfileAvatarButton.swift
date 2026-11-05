//
//  ProfileAvatarButton.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 8/22/26.
//

import SwiftUI
import BaseColors
import LoggingKit
import SDWebImageSwiftUI

struct ProfileAvatarButton: View {
    @Environment(ViewManager.self) private var viewManager
    @Environment(ServerViewModel.self) private var serverViewModel
    @State private var showProfile = false
    @State private var pendingSignOut = false

    var body: some View {
        Button {
            showProfile = true
        } label: {
            if let url = serverViewModel.profileImageURL {
                WebImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    fallbackIcon
                }
                .onFailure { error in
                    AppLogger.error("Failed to load user avatar", error, tag: "ProfileAvatarButton")
                }
                .frame(width: 40, height: 40)
                .clipShape(Circle())
            } else {
                fallbackIcon
            }
        }
        .sheet(isPresented: $showProfile, onDismiss: {
            if pendingSignOut {
                pendingSignOut = false
                viewManager.signOut()
            }
        }) {
            SettingsView(onSignOut: { pendingSignOut = true })
        }
        .padding(.trailing, 20)
    }

    private var fallbackIcon: some View {
        Image(systemName: "person.fill")
            .font(.system(size: 17))
            .foregroundStyle(Color.subFour)
            .padding(10)
            .background(){
                Circle()
                    .fill(Color.subTwo)
            }
    }
}
