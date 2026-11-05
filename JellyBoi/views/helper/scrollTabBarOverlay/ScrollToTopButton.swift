//
//  ScrollToTopButton.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 9/25/24.
//

import SwiftUI

struct ScrollToTopButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 13, weight: .bold))
                Text("Top")
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(Color.appAccent, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
