//
//  DownloadActivityWidget.swift
//  JellyBoiWidgetExtension
//
//  Created by Garrett Butchko on 10/20/26.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct DownloadActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DownloadActivityAttributes.self) { context in
            // Lock screen / Banner UI
            LockScreenDownloadView(state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.85))
                .activitySystemActionForegroundColor(Color.white)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        Image(systemName: context.state.isCompleted ? "checkmark.circle.fill" : "arrow.down.circle.fill")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(context.state.isCompleted ? Color.green : Color.purple)
                    }
                    .padding(.leading, 4)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(Int(context.state.progress * 100))%")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(context.state.isCompleted ? Color.green : Color.primary)

                        if let detail = context.state.detailText, !detail.isEmpty {
                            Text(detail)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.trailing, 4)
                }

                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.title)
                            .font(.system(size: 14, weight: .bold))
                            .lineLimit(1)
                            .foregroundStyle(.primary)

                        if let subtitle = context.state.subtitle, !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 6) {
                        ProgressView(value: context.state.progress)
                            .tint(context.state.isCompleted ? Color.green : Color.purple)

                        HStack {
                            if context.state.isCompleted {
                                Text("Ready to watch offline")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                            } else if context.state.itemsRemaining > 1 {
                                Text("\(context.state.itemsRemaining) items remaining")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                            } else if let subtitle = context.state.subtitle {
                                Text(subtitle)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if let detail = context.state.detailText {
                                Text(detail)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.top, 4)
                }
            } compactLeading: {
                Image(systemName: context.state.isCompleted ? "checkmark.circle.fill" : "arrow.down.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(context.state.isCompleted ? Color.green : Color.purple)
            } compactTrailing: {
                if context.state.isCompleted {
                    Text("Done")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.green)
                } else {
                    Text("\(Int(context.state.progress * 100))%")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.purple)
                }
            } minimal: {
                if context.state.isCompleted {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.green)
                } else {
                    ProgressView(value: context.state.progress)
                        .progressViewStyle(.circular)
                        .tint(Color.purple)
                }
            }
            .widgetURL(URL(string: "jellyboi://downloads"))
            .keylineTint(Color.purple.opacity(0.6))
        }
    }
}

// MARK: - Lock Screen Banner View

private struct LockScreenDownloadView: View {
    let state: DownloadActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                ZStack {
                    Circle()
                        .fill(state.isCompleted ? Color.green.opacity(0.2) : Color.purple.opacity(0.2))
                        .frame(width: 36, height: 36)

                    Image(systemName: state.isCompleted ? "checkmark.circle.fill" : "arrow.down.circle.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(state.isCompleted ? Color.green : Color.purple)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(state.title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    if let subtitle = state.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(Int(state.progress * 100))%")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(state.isCompleted ? Color.green : .white)

                    if let detail = state.detailText, !detail.isEmpty {
                        Text(detail)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.65))
                    }
                }
            }

            ProgressView(value: state.progress)
                .tint(state.isCompleted ? Color.green : Color.purple)

            HStack {
                if state.isCompleted {
                    Text("Ready to watch offline")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.65))
                } else if state.itemsRemaining > 1 {
                    Text("\(state.itemsRemaining) items remaining in queue")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.65))
                } else {
                    Text("Downloading to device")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.65))
                }

                Spacer()

                Text("JellyBoi")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .padding(16)
        .widgetURL(URL(string: "jellyboi://downloads"))
    }
}
