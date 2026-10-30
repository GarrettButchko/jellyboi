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
                    let isEp = isEpisodeThumbnail(for: context.state)
                    if context.state.isSingleElement, let imageData = context.state.posterImageData {
                        PosterView(
                            imageData: imageData,
                            status: context.state.status,
                            isEpisode: isEp,
                            width: isEp ? 26 : 14,
                            height: isEp ? 17 : 21,
                            cornerRadius: isEp ? 4 : 3.5
                        )
                    } else {
                        // Default: Jellyboi SVG mascot
                        Image("Jellyboi")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 14, height: 14)
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .padding(.leading, 6)
                .padding(.vertical, 2)
            } compactTrailing: {
                // Percentage instead of progress ring with padding
                Text(context.state.compactPercentageText)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(context.state.compactPercentageColor)
                    .padding(.trailing, 6)
                    .padding(.vertical, 2)
            } minimal: {
                Group {
                    if context.state.status == .queued || context.state.status == .completed {
                        Image("Jellyboi")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 12, height: 12)
                            .foregroundStyle(Color.accentColor)
                    } else {
                        Text("\(context.state.progressPercent)%")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Color.white)
                    }
                }
                .padding(4)
            }
            .widgetURL(URL(string: "jellyboi://downloads"))
            .keylineTint(Color.accentColor.opacity(0.4))
        }
    }
}

// MARK: - Lock Screen & Expanded Dynamic Island Banner View

private struct LockScreenDownloadView: View {
    let state: DownloadActivityAttributes.ContentState
    var isDynamicIsland: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            leadingArtworkOrIcon

            VStack(alignment: .leading, spacing: 6) {
                Text(state.title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)

                ProgressView(value: state.status == .queued ? 0.0 : min(max(state.progress, 0.0), 1.0))
                    .tint(Color.accentColor)

                bottomStatusRow
            }
        }
        .padding(.horizontal, isDynamicIsland ? 6 : 16)
        .padding(.vertical, isDynamicIsland ? 6 : 14)
        .widgetURL(URL(string: "jellyboi://downloads"))
    }

    @ViewBuilder
    private var leadingArtworkOrIcon: some View {
        let isEp = isEpisodeThumbnail(for: state)
        let thumbWidth: CGFloat = isEp ? 64 : 32
        let thumbHeight: CGFloat = isEp ? 40 : 48
        let radius: CGFloat = 6.5

        if state.isSingleElement, let imageData = state.posterImageData {
            // Single element with artwork: SHOW POSTER OR EPISODE THUMBNAIL
            PosterView(
                imageData: imageData,
                status: state.status,
                isEpisode: isEp,
                width: thumbWidth,
                height: thumbHeight,
                cornerRadius: radius
            )
        } else {
            // Default: Jellyboi SVG in card container
            ZStack {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color.white.opacity(0.08))

                Image("Jellyboi")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: isEp ? 24 : 20, height: isEp ? 24 : 20)
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: thumbWidth, height: thumbHeight)
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
            )
        }
    }

    @ViewBuilder
    private var bottomStatusRow: some View {
        if !state.isSingleElement {
            // Multiple items: show percent only under the bar (amount of items is only shown once in the title above)
            HStack(spacing: 4) {
                Image(systemName: state.status.icon)
                    .font(.system(size: 10, weight: .medium))

                Text(state.percentageText)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .monospacedDigit()

                Spacer()
            }
            .foregroundStyle(Color.white.opacity(0.75))
        } else {
            // Single element: shows icon + status (e.g. 1 min left / Converting / 3 episodes left) and percent on the right
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: state.status.icon)
                        .font(.system(size: 10, weight: .medium))

                    Text(state.statusDetail)
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                }
                .foregroundStyle(Color.white.opacity(0.65))
                .lineLimit(1)

                Spacer(minLength: 8)

                Text(state.percentageText)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.white.opacity(0.75))
            }
        }
    }
}

// MARK: - Poster / Thumbnail View

private struct PosterView: View {
    let imageData: Data?
    let status: DownloadStatus
    var isEpisode: Bool = false
    var width: CGFloat = 32
    var height: CGFloat = 48
    var cornerRadius: CGFloat = 6.5

    var body: some View {
        Group {
            #if canImport(UIKit)
            if let imageData, let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: isEpisode ? .fit : .fill)
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

            Image("Jellyboi")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: max(8, width * 0.45), height: max(8, height * 0.45))
                .foregroundStyle(Color.accentColor)
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
    let status: DownloadStatus
    var size: CGFloat = 20
    var lineWidth: CGFloat = 2

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.15), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: status.isCompleted ? 1.0 : (status.isQueued ? 0.05 : max(0.05, CGFloat(progress))))
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))

            Image(systemName: status.icon)
                .font(.system(size: size * 0.45, weight: .bold))
                .foregroundStyle(Color.accentColor)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Aspect Ratio Helper

private func isEpisodeThumbnail(for state: DownloadActivityAttributes.ContentState) -> Bool {
    if state.isEpisode { return true }
    #if canImport(UIKit)
    if let data = state.posterImageData, let image = UIImage(data: data) {
        return image.size.width > image.size.height
    }
    #endif
    return false
}
