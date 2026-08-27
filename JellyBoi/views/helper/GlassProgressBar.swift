//
//  GlassProgressBar.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 8/25/26.
//

import SwiftUI
import BaseColors

struct GlassProgressBar: View {
    let progress: Double
    var barWidth: CGFloat = 50
    var barHeight: CGFloat = 4
    var label: String? = nil

    var body: some View {
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
        .glassEffect(.clear.tint(Color.main.opacity(0.6)), in: Capsule())
    }
}
