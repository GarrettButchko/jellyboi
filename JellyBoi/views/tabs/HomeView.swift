//
//  HomeView.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 8/19/26.
//

import SwiftUI

struct HomeView: View {
    var body: some View {
        Text("Home")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .topTrailing) {
                ProfileAvatarButton()
            }
    }
}

#Preview {
    HomeView()
}
