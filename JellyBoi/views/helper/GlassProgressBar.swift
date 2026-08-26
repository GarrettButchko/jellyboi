//
//  GlassProgressBar.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 8/25/26.
//

import SwiftUI

struct GlassProgressBar: View {
    let progress: Double
    var barWidth: CGFloat = 50
    var barHeight: CGFloat = 4
    var label: String? = nil

    var body: some View {
        HStack(spacing: 8) {
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.35))
                    .frame(width: barWidth, height: barHeight)
                Capsule()
                    .fill(.white)
                    .frame(width: barWidth, height: barHeight)
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: barWidth * progress)
                    }
            }
            if let label {
                Text(label)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .glassEffect(.clear.tint(.black.opacity(0.35)), in: Capsule())
    }
}
