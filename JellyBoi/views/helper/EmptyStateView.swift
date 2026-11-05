//
//  EmptyStateView.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 8/28/26.
//

import SwiftUI
import BaseColors

/// A reusable centered empty / error state used across tabs when content is unavailable.
struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var buttonTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(Color.mainOpp.opacity(0.5))

            Text(title)
                .font(.system(.headline, design: .rounded, weight: .semibold))
                .foregroundStyle(Color.mainOpp)
                .multilineTextAlignment(.center)

            Text(message)
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(Color.mainOpp.opacity(0.6))
                .multilineTextAlignment(.center)

            if let buttonTitle, let action {
                Button(buttonTitle, action: action)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Color.bg)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.appAccent, in: Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 40)
        .padding(.top, 40)
    }
}
