//
//  CircleScrollToTopButton.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 10/23/26.
//

import SwiftUI

struct CircleScrollToTopButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.up")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(Color.appAccent, in: Circle())
        }
        .buttonStyle(.plain)
    }
}
