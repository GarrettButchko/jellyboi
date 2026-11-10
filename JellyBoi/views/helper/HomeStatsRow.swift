//
//  HomeStatsRow.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 10/30/26.
//

import SwiftUI
import BaseColors

// MARK: - Home Stat Category

enum HomeStatCategory: String, Identifiable, Hashable, CaseIterable {
    case movies
    case shows
    case episodes
    case watching
    case favorites
    case completed
    case watchedHours

    var id: String { rawValue }
}

// MARK: - Home Stats Row

struct HomeStatsRow: View {
    var moviesCount: Int = 0
    var tvSeriesCount: Int = 0
    var episodeCount: Int = 0
    var inProgressCount: Int = 0
    var favoritesCount: Int = 0
    var completedCount: Int = 0
    var watchedHours: Int = 0
    var onSelectStat: ((HomeStatCategory) -> Void)? = nil

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 10) {
                HomeStatBubble(label: "Movies", value: moviesCount, icon: "film") {
                    onSelectStat?(.movies)
                }
                HomeStatsDoubleBubble(
                    leftLabel: "Shows", leftValue: tvSeriesCount, leftIcon: "tv",
                    rightLabel: "Episodes", rightValue: episodeCount, rightIcon: "film.stack",
                    onSelectLeft: { onSelectStat?(.shows) },
                    onSelectRight: { onSelectStat?(.episodes) }
                )
                HomeStatBubble(label: "Watching", value: inProgressCount, icon: "play.circle") {
                    onSelectStat?(.watching)
                }
                HomeStatBubble(label: "Favorites", value: favoritesCount, icon: "heart.fill") {
                    onSelectStat?(.favorites)
                }
                HomeStatBubble(label: "Completed", value: completedCount, icon: "checkmark.circle.fill") {
                    onSelectStat?(.completed)
                }
                HomeStatBubble(label: "Hrs Watched", value: watchedHours, icon: "clock.fill") {
                    onSelectStat?(.watchedHours)
                }
            }
            .padding(.horizontal, 16)
        }
        .scrollClipDisabled()
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
    var onSelect: (() -> Void)? = nil

    var body: some View {
        Button {
            onSelect?()
        } label: {
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
            .glassEffect(.regular.interactive(), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(StatPressButtonStyle())
        .accessibilityLabel("\(value) \(label)")
    }
}

struct HomeStatsDoubleBubble: View {
    let leftLabel: String
    let leftValue: Int
    let leftIcon: String
    let rightLabel: String
    let rightValue: Int
    let rightIcon: String
    var onSelectLeft: (() -> Void)? = nil
    var onSelectRight: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            Button {
                onSelectLeft?()
            } label: {
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
                .contentShape(Rectangle())
            }
            .buttonStyle(StatPressButtonStyle())
            .accessibilityLabel("\(leftValue) \(leftLabel)")

            Text("•")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.mainOpp.opacity(0.3))

            Button {
                onSelectRight?()
            } label: {
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
                .contentShape(Rectangle())
            }
            .buttonStyle(StatPressButtonStyle())
            .accessibilityLabel("\(rightValue) \(rightLabel)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: Capsule())
    }
}

private struct StatPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
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
