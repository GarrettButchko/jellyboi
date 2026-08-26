//
//  PlayProgressPill.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 8/25/26.
//

import SwiftUI
import BaseColors
import JellyfinAPI

struct PlayProgressPill: View {
    let item: BaseItemDto

    private var progress: Double {
        guard let percent = item.userData?.playedPercentage else { return 0 }
        return min(max(percent / 100, 0), 1)
    }

    private var timeRemainingLabel: String? {
        guard let ticks = item.runTimeTicks,
              let percent = item.userData?.playedPercentage,
              percent > 0 else { return nil }
        let totalSeconds = Int(ticks / 10_000_000)
        let remainingSeconds = totalSeconds - Int(Double(totalSeconds) * percent / 100)
        guard remainingSeconds > 60 else { return nil }
        let hours = remainingSeconds / 3600
        let minutes = (remainingSeconds % 3600) / 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "play.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.main)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 25, style: .continuous)
                        .fill(Color.main.opacity(0.5))
                        .frame(height: 10)
                    RoundedRectangle(cornerRadius: 25, style: .continuous)
                        .fill(Color.main)
                        .frame(height: 10)
                        .mask(alignment: .leading) {
                            Rectangle()
                                .frame(width: proxy.size.width * progress)
                        }
                }
            }
            .frame(width: 60, height: 10)

            if let label = timeRemainingLabel {
                Text(label)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.main)
                    .frame(width: 50)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(Color.mainOpp, in: Capsule())
    }
}
