//
//  HomeStatsRow.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 10/30/26.
//

import SwiftUI
import BaseColors

// MARK: - Home Stats Row

struct HomeStatsRow: View {
    var moviesCount: Int = 0
    var tvSeriesCount: Int = 0
    var episodeCount: Int = 0
    var inProgressCount: Int = 0
    var favoritesCount: Int = 0
    var completedCount: Int = 0
    var watchedHours: Int = 0

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                HomeStatBubble(label: "Movies", value: moviesCount, icon: "film")
                HomeStatsDoubleBubble(
                    leftLabel: "Shows", leftValue: tvSeriesCount, leftIcon: "tv",
                    rightLabel: "Episodes", rightValue: episodeCount, rightIcon: "film.stack"
                )
                HomeStatBubble(label: "Watching", value: inProgressCount, icon: "play.circle")
                HomeStatBubble(label: "Favorites", value: favoritesCount, icon: "heart.fill")
                HomeStatBubble(label: "Completed", value: completedCount, icon: "checkmark.circle.fill")
                HomeStatBubble(label: "Hrs Watched", value: watchedHours, icon: "clock.fill")
            }
            .padding(.horizontal, 16)
        }
        .scrollIndicators(.hidden)
    }

    /// Convenience factory rendering a static skeleton placeholder stats row.
    static var placeholder: some View {
        HomeStatsRow(
            moviesCount: 999,
            tvSeriesCount: 99,
            episodeCount: 999,
            inProgressCount: 99,
            favoritesCount: 99,
            completedCount: 99,
            watchedHours: 99
        )
        .skeleton()
    }
}

// MARK: - Stat Bubbles

struct HomeStatBubble: View {
    let label: String
    let value: Int
    let icon: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.mainOpp)
            Text("\(value)")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(Color.mainOpp)
            Text(label)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(Color.mainOpp.opacity(0.6))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: Capsule())
    }
}

struct HomeStatsDoubleBubble: View {
    let leftLabel: String
    let leftValue: Int
    let leftIcon: String
    let rightLabel: String
    let rightValue: Int
    let rightIcon: String

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: leftIcon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.mainOpp)
                Text("\(leftValue)")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.mainOpp)
                Text(leftLabel)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.mainOpp.opacity(0.6))
            }

            Text("•")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.mainOpp.opacity(0.3))

            HStack(spacing: 5) {
                Image(systemName: rightIcon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.mainOpp)
                Text("\(rightValue)")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.mainOpp)
                Text(rightLabel)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.mainOpp.opacity(0.6))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: Capsule())
    }
}

#Preview {
    VStack(spacing: 20) {
        HomeStatsRow(
            moviesCount: 120,
            tvSeriesCount: 14,
            episodeCount: 340,
            inProgressCount: 5,
            favoritesCount: 22,
            completedCount: 88,
            watchedHours: 412
        )

        HomeStatsRow.placeholder
    }
    .background(Color.bg)
}
