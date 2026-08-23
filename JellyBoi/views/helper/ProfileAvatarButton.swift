//
//  ProfileAvatarButton.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 8/22/26.
//

import SwiftUI
import BaseColors
import JellyfinAPI
import LoggingKit

struct ProfileAvatarButton: View {
    @EnvironmentObject private var viewManager: ViewManager
    @Environment(ServerViewModel.self) private var serverViewModel
    @State private var showProfile = false
    @State private var pendingSignOut = false

    private var profileImageURL: URL? {
        guard let client = serverViewModel.client,
              let user = serverViewModel.currentUser,
              let userID = user.id,
              user.primaryImageTag != nil
        else { return nil }
        return client.url(with: Paths.getUserImage(parameters: .init(userID: userID)))
    }

    var body: some View {
        Button {
            showProfile = true
        } label: {
            if let url = profileImageURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure(let error):
                        let _ = AppLogger.error("Failed to load user avatar", error, tag: "ProfileAvatarButton")
                        fallbackIcon
                    default:
                        fallbackIcon
                    }
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
            ProfileView(onSignOut: { pendingSignOut = true })
        }
        .safeAreaPadding(.top)
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
