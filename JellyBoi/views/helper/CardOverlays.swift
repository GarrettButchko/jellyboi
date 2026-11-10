//
//  ProgressBar.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 8/25/26.
//

import SwiftUI
import BaseColors

extension Color {
    static var cardOverlay: Color {
        Color.main.opacity(0.7)
    }
}

struct ProgressBar: View {
    @Environment(AppPreferences.self) private var preferencesEnvironment: AppPreferences?

    let progress: Double
    var barWidth: CGFloat = 50
    var barHeight: CGFloat = 4
    var label: String? = nil

    private var isVisible: Bool {
        (preferencesEnvironment ?? AppPreferences.shared).showProgressBar
    }

    @ViewBuilder
    var body: some View {
        if isVisible {
            HStack(spacing: 8) {
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.mainOpp.opacity(0.35))
                        .frame(width: barWidth, height: barHeight)
                    Capsule()
                        .fill(Color.mainOpp)
                        .frame(width: barWidth, height: barHeight)
                        .mask(alignment: .leading) {
                            Rectangle().frame(width: barWidth * progress)
                        }
                }
                if let label {
                    Text(label + " left")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.mainOpp)
                        .fixedSize()
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.cardOverlay, in: Capsule())
        }
    }
}

struct EpisodeBadge: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    init(text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.mainOpp)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.cardOverlay, in: Capsule())
    }
}

struct CheckmarkBadge: View {
    var body: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(Color.mainOpp)
            .padding(6)
            .background(Color.cardOverlay, in: Capsule())
    }
}
