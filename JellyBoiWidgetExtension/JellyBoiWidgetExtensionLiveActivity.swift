//
//  DownloadActivityWidget.swift
//  JellyBoiWidgetExtension
//
//  Created by Garrett Butchko on 10/20/26.
//

import ActivityKit
import WidgetKit
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct DownloadActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DownloadActivityAttributes.self) { context in
            // Lock screen / Banner UI
            LockScreenDownloadView(state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.75))
                .activitySystemActionForegroundColor(Color.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    EmptyView()
                }
                DynamicIslandExpandedRegion(.trailing) {
                    EmptyView()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    LockScreenDownloadView(state: context.state, isDynamicIsland: true)
                }
            } compactLeading: {
                Group {
                    if context.state.isSingleElement {
                        PosterView(
                            imageData: context.state.posterImageData,
                            isCompleted: context.state.isCompleted,
                            statusIcon: context.state.statusIcon,
                            isQueued: context.state.isQueued,
                            width: 14,
                            height: 21,
                            cornerRadius: 3.5
                        )
                    } else {
                        // Multiple unrelated elements: SHOW ONLY THE ICON!
                        Image(systemName: context.state.statusIcon)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(iconTint(for: context.state))
                    }
                }
                .padding(.leading, 6)
                .padding(.vertical, 2)
            } compactTrailing: {
                // Percentage instead of progress ring with padding
                Text(compactPercentageText(for: context.state))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(compactPercentageColor(for: context.state))
                    .padding(.trailing, 6)
                    .padding(.vertical, 2)
            } minimal: {
                Group {
                    if context.state.isQueued {
                        Image(systemName: "clock")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.orange)
                    } else if context.state.isCompleted {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.green)
                    } else {
                        Text("\(Int(context.state.progress * 100))%")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Color.white)
                    }
                }
                .padding(4)
            }
            .widgetURL(URL(string: "jellyboi://downloads"))
            .keylineTint(Color.indigo.opacity(0.4))
        }
    }

    private func iconTint(for state: DownloadActivityAttributes.ContentState) -> Color {
        if state.isCompleted {
            return Color.green
        }
        if state.isQueued {
            return Color.orange
        }
        if state.isConverting || state.statusIcon == "arrow.triangle.2.circlepath" {
            return Color.purple
        }
        return Color.indigo
    }

    private func compactPercentageText(for state: DownloadActivityAttributes.ContentState) -> String {
        if state.isCompleted {
            return "100%"
        }
        if state.isQueued {
            return "Queued"
        }
        return "\(Int(state.progress * 100))%"
    }

    private func compactPercentageColor(for state: DownloadActivityAttributes.ContentState) -> Color {
        if state.isCompleted {
            return Color.green
        }
        if state.isQueued {
            return Color.orange
        }
        return Color.white.opacity(0.9)
    }
}

// MARK: - Lock Screen & Expanded Dynamic Island Banner View

private struct LockScreenDownloadView: View {
    let state: DownloadActivityAttributes.ContentState
    var isDynamicIsland: Bool = false

    private var progressTint: Color {
        if state.isCompleted {
            return Color.green
        }
        if state.isQueued {
            return Color.orange
        }
        if state.isConverting || state.statusIcon == "arrow.triangle.2.circlepath" {
            return Color.purple
        }
        return Color.indigo
    }

    private var percentageText: String {
        if state.isCompleted {
            return "Done"
        }
        if state.isQueued {
            return "Queued"
        }
        return "\(Int(state.progress * 100))%"
    }

    var body: some View {
        HStack(spacing: 12) {
            leadingArtworkOrIcon

            VStack(alignment: .leading, spacing: 6) {
                Text(state.title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)

                ProgressView(value: state.isQueued ? 0.0 : state.progress)
                    .tint(progressTint)

                bottomStatusRow
            }
        }
        .padding(.horizontal, isDynamicIsland ? 6 : 16)
        .padding(.vertical, isDynamicIsland ? 6 : 14)
        .widgetURL(URL(string: "jellyboi://downloads"))
    }

    @ViewBuilder
    private var leadingArtworkOrIcon: some View {
        if state.isSingleElement {
            // Exactly 1 element (movie, episode, series, collection): SHOW POSTER
            PosterView(
                imageData: state.posterImageData,
                isCompleted: state.isCompleted,
                statusIcon: state.statusIcon,
                isQueued: state.isQueued,
                width: 32,
                height: 48,
                cornerRadius: 6.5
            )
        } else {
            // Multiple unrelated elements: SHOW ONLY THE ICON!
            ProgressRingIndicator(
                progress: state.progress,
                isCompleted: state.isCompleted,
                icon: state.statusIcon,
                isQueued: state.isQueued,
                size: 32,
                lineWidth: 3
            )
            .frame(width: 32, height: 48)
        }
    }

    @ViewBuilder
    private var bottomStatusRow: some View {
        if !state.isSingleElement {
            // Multiple items: show percent only under the bar (amount of items is only shown once in the title above)
            HStack(spacing: 4) {
                Image(systemName: state.statusIcon)
                    .font(.system(size: 10, weight: .medium))

                Text(percentageText)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .monospacedDigit()

                Spacer()
            }
            .foregroundStyle(Color.white.opacity(0.75))
        } else {
            // Single element: shows icon + status (e.g. 1 min left / Converting / 3 episodes left) and percent on the right
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: state.statusIcon)
                        .font(.system(size: 10, weight: .medium))

                    Text(statusDetail(for: state))
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                }
                .foregroundStyle(Color.white.opacity(0.65))
                .lineLimit(1)

                Spacer(minLength: 8)

                Text(percentageText)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.white.opacity(0.75))
            }
        }
    }
}

// MARK: - Poster View (Full 2:3 Aspect Ratio)

private struct PosterView: View {
    let imageData: Data?
    let isCompleted: Bool
    var statusIcon: String? = nil
    var isQueued: Bool = false
    var width: CGFloat = 32
    var height: CGFloat = 48
    var cornerRadius: CGFloat = 6.5

    private var placeholderIcon: String {
        if isCompleted {
            return "checkmark"
        }
        if let icon = statusIcon {
            return icon
        }
        if isQueued {
            return "clock"
        }
        return "arrow.down"
    }

    private var placeholderColor: Color {
        if isCompleted {
            return Color.green
        }
        if isQueued {
            return Color.orange
        }
        if statusIcon == "arrow.triangle.2.circlepath" {
            return Color.purple
        }
        return Color.indigo
    }

    var body: some View {
        Group {
            #if canImport(UIKit)
            if let imageData, let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: width, height: height)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                    )
            } else {
                placeholderView
            }
            #else
            placeholderView
            #endif
        }
    }

    private var placeholderView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.08))

            Image(systemName: placeholderIcon)
                .font(.system(size: max(8, width * 0.4), weight: .bold))
                .foregroundStyle(placeholderColor)
        }
        .frame(width: width, height: height)
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
        )
    }
}

// MARK: - Progress Ring Indicator

private struct ProgressRingIndicator: View {
    let progress: Double
    let isCompleted: Bool
    var icon: String = "arrow.down"
    var isQueued: Bool = false
    var size: CGFloat = 20
    var lineWidth: CGFloat = 2

    private var accentColor: Color {
        if isCompleted {
            return Color.green
        }
        if isQueued {
            return Color.orange
        }
        if icon == "arrow.triangle.2.circlepath" {
            return Color.purple
        }
        return Color.indigo
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.15), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: isCompleted ? 1.0 : (isQueued ? 0.05 : max(0.05, CGFloat(progress))))
                .stroke(accentColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))

            Image(systemName: icon)
                .font(.system(size: max(6, size * 0.42), weight: .bold))
                .foregroundStyle(accentColor)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Helpers

private func statusDetail(for state: DownloadActivityAttributes.ContentState) -> String {
    if state.isCompleted {
        return "Ready offline"
    }
    if state.isQueued {
        if state.itemsRemaining > 1 {
            return "\(state.itemsRemaining) items queued"
        }
        return "Queued"
    }
    if state.isConverting || state.statusIcon == "arrow.triangle.2.circlepath" {
        if state.itemsRemaining > 1 {
            return "\(state.itemsRemaining) left • Converting"
        }
        return "Converting"
    }
    if let extra = cleanExtraInfo(state.detailText, itemsRemaining: state.itemsRemaining) {
        return extra
    }
    if let subtitle = state.subtitle, !subtitle.isEmpty {
        return subtitle
    }
    if state.itemsRemaining > 1 {
        return "\(state.itemsRemaining) items left"
    }
    return "Downloading"
}

private func cleanExtraInfo(_ detailText: String?, itemsRemaining: Int) -> String? {
    guard let detailText = detailText, !detailText.isEmpty else { return nil }
    let components = detailText.components(separatedBy: "•").map { $0.trimmingCharacters(in: .whitespaces) }
    let nonPercent = components.filter { !$0.contains("%") }

    for item in nonPercent {
        if itemsRemaining > 1 && (item.contains("item") || item.contains("episode")) {
            continue
        }
        return item
    }
    return nonPercent.first
}
