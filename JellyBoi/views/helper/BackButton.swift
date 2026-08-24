//
//  BackButton.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 8/24/26.
//

import SwiftUI
import BaseColors

struct BackButton: View {
    private let action: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    /// Pass a custom action, or omit it to dismiss the current presentation/navigation entry.
    init(action: (() -> Void)? = nil) {
        self.action = action
    }

    var body: some View {
        Button {
            if let action {
                action()
            } else {
                dismiss()
            }
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.mainOpp)
                .padding(14)
        }
        .glassEffect(.regular.interactive(), in: Circle())
    }
}

#Preview {
    ZStack {
        Color.bg.ignoresSafeArea()
        VStack(spacing: 20) {
            BackButton()
            BackButton { print("custom") }
        }
    }
}
