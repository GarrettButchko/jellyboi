//
//  ActiveDownloadFloatingBar.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 10/23/26.
//

import SwiftUI
import BaseColors
import JellyfinAPI
import MarqueeText
import SDWebImageSwiftUI

struct ActiveDownloadFloatingBar: View {
    let activeDownloads: [DownloadItem]
    let onTap: () -> Void

    @Environment(ServerViewModel.self) private var serverViewModel
    @Environment(LibraryViewModel.self) private var libraryViewModel

    private var singleDownloadItem: DownloadItem? {
        activeDownloads.count == 1 ? activeDownloads.first : nil
    }

    private var commonGroupInfo: ShowDownloadGroup? {
        guard !activeDownloads.isEmpty else { return nil }
        var commonGroup: DownloadGroupInfo? = nil

        for item in activeDownloads {
            guard let group = item.group else { return nil }
            if let existing = commonGroup {
                if existing.id != group.id {
                    return nil
                }
            } else {
                commonGroup = group
            }
        }

        guard let commonGroup else { return nil }
        return ShowDownloadGroup(
            id: commonGroup.id,
            seriesName: commonGroup.title,
            groupInfo: commonGroup,
            activeDownloads: activeDownloads,
            completedDownloads: []
        )
    }

    private var overallProgress: Double {
        guard !activeDownloads.isEmpty else { return 0 }
        let total = activeDownloads.reduce(0.0) { $0 + $1.progress }
        return total / Double(activeDownloads.count)
    }

    private var barTitle: String {
        if let single = singleDownloadItem {
            return single.title
        } else if let group = commonGroupInfo {
            return group.seriesName
        } else {
            return "\(activeDownloads.count) items"
        }
    }

    private var barSubtitle: String {
        if !activeDownloads.isEmpty && activeDownloads.allSatisfy({ $0.status == .queued }) {
            return "Queued"
        } else {
            return "\(percent)%"
        }
    }

    private var ringIcon: String {
        if activeDownloads.contains(where: { $0.status == .converting || $0.status == .finalizing }) {
            return "arrow.triangle.2.circlepath"
        } else if activeDownloads.contains(where: { $0.status == .downloading }) {
            return "arrow.down"
        } else if activeDownloads.contains(where: { $0.status == .failed }) {
            return "exclamationmark.triangle.fill"
        } else if !activeDownloads.isEmpty && activeDownloads.allSatisfy({ $0.status == .queued }) {
            return "clock"
        } else if let icon = activeDownloads.first?.statusIcon {
            return icon
        } else {
            return "arrow.down"
        }
    }

    private var percent: Int {
        Int(overallProgress * 100)
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                leadingIndicatorView

                VStack(alignment: .leading, spacing: 1) {
                    MarqueeText(
                        text: barTitle,
                        font: UIFont.systemFont(ofSize: 12.5, weight: .semibold),
                        leftFade: 6,
                        rightFade: 10,
                        startDelay: 2.0,
                        alignment: .leading
                    )
                    .makeCompact()
                    .foregroundStyle(Color.mainOpp)
                    .id(barTitle)
                    .transition(.opacity)

                    subtitleContentView
                }
                .frame(maxWidth: 140, alignment: .leading)

                Image(systemName: "chevron.up")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(Color.mainOpp.opacity(0.4))
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .frame(height: 42)
            .glassEffect(.regular.interactive(), in: Capsule())
            .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 3)
            .animation(.spring(response: 0.38, dampingFraction: 0.78), value: activeDownloads.count > 1)
            .animation(.spring(response: 0.38, dampingFraction: 0.78), value: activeDownloads.count)
            .animation(.spring(response: 0.38, dampingFraction: 0.78), value: singleDownloadItem?.id)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var leadingIndicatorView: some View {
        if let singleItem = singleDownloadItem {
            DownloadThumbnailView(
                item: singleItem,
                client: serverViewModel.client,
                libraryViewModel: libraryViewModel,
                size: .compact
            )
            .id("thumb-single-\(singleItem.id)")
            .transition(.opacity.combined(with: .scale(scale: 0.85)))
        } else if let group = commonGroupInfo {
            DownloadThumbnailView(
                group: group,
                client: serverViewModel.client,
                libraryViewModel: libraryViewModel,
                size: .compact
            )
            .id("thumb-group-\(group.id)")
            .transition(.opacity.combined(with: .scale(scale: 0.85)))
        } else {
            // Circular progress ring
            ZStack {
                Circle()
                    .stroke(Color.mainOpp.opacity(0.12), lineWidth: 2.2)
                Circle()
                    .trim(from: 0, to: max(0.06, CGFloat(overallProgress)))
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.smooth(duration: 0.3), value: overallProgress)

                Image(systemName: ringIcon)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.accentColor)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: 20, height: 20)
            .id("multi-ring")
            .transition(.opacity.combined(with: .scale(scale: 0.85)))
        }
    }

    @ViewBuilder
    private var subtitleContentView: some View {
        if let singleItem = singleDownloadItem {
            if singleItem.status == .failed {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.red)
                    Text(singleItem.errorMessage ?? "Download or conversion failed")
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.red)
                        .lineLimit(1)
                }
                .id("sub-single-fail-\(singleItem.id)")
                .transition(.opacity)
            } else {
                HStack(spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: singleItem.statusIcon)
                            .font(.system(size: 9.5, weight: .medium))
                        Text(singleItem.statusText)
                    }
                    .font(.system(size: 10.5, design: .rounded))
                    .foregroundStyle(Color.mainOpp.opacity(0.6))

                    Spacer(minLength: 4)

                    if singleItem.status != .queued {
                        Text(singleItem.formattedPercentage)
                            .font(.system(size: 10.5, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.mainOpp.opacity(0.8))
                    }
                }
                .id("sub-single-ok-\(singleItem.id)")
                .transition(.opacity)
            }
        } else if let group = commonGroupInfo {
            let itemWord = group.groupInfo?.type == .collection ? (group.episodesLeft == 1 ? "item" : "items") : (group.episodesLeft == 1 ? "episode" : "episodes")

            let subtitle: String = {
                if group.isAllFailed {
                    return "\(group.episodesLeft) \(itemWord) left (Failed)"
                } else if let timeRemaining = group.formattedTimeRemaining {
                    return "\(group.episodesLeft) left • \(timeRemaining)"
                } else {
                    return "\(group.episodesLeft) \(itemWord) left"
                }
            }()

            let activeIcon: String? = {
                if group.activeDownloads.contains(where: { $0.status == .converting || $0.status == .finalizing }) {
                    return "arrow.triangle.2.circlepath"
                } else if group.activeDownloads.contains(where: { $0.status == .downloading }) {
                    return "arrow.down"
                } else if group.isAllFailed {
                    return "exclamationmark.triangle.fill"
                } else if group.isAllQueued {
                    return "clock"
                }
                return nil
            }()

            HStack(spacing: 4) {
                HStack(spacing: 4) {
                    if let icon = activeIcon {
                        Image(systemName: icon)
                            .font(.system(size: 9.5, weight: .medium))
                    }
                    Text(subtitle)
                }
                .font(.system(size: 10.5, design: .rounded))
                .foregroundStyle(group.isAllFailed ? Color.red : Color.mainOpp.opacity(0.6))

                Spacer(minLength: 4)

                Text("\(percent)%")
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.mainOpp.opacity(0.8))
            }
            .id("sub-group-\(group.id)")
            .transition(.opacity)
        } else {
            Text(barSubtitle)
                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                .foregroundStyle(Color.mainOpp.opacity(0.6))
                .lineLimit(1)
                .id("sub-multi")
                .transition(.opacity)
        }
    }
}
