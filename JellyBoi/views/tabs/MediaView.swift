//
//  MediaView.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 8/19/26.
//

import SwiftUI

struct MediaView: View {
    var body: some View {
        Text("Media")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .topTrailing) {
                ProfileAvatarButton()
            }
    }
}

#Preview {
    MediaView()
}
