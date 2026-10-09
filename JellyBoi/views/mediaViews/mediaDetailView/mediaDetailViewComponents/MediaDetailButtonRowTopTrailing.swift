//
//  MediaDetailButtonRowTopTrailing.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 9/6/26.
//

import SwiftUI
import BaseColors

struct MediaDetailButtonRowTopTrailing: View {
    typealias ButtonItem = (systemName: String, action: () -> Void)

    let isFavorited: Bool
    let isDownloaded: Bool
    let isDownloading: Bool
    let downloadProgress: Double
    let episodesLeft: Int?
    let onOpenSheet: (() -> Void)?
    private let onFavorite: () -> Void
    private let onDownload: () -> Void

    @Namespace private var namespace

    init(
        isFavorited: Bool = false,
        isDownloaded: Bool = false,
        isDownloading: Bool = false,
        downloadProgress: Double = 0.0,
        episodesLeft: Int? = nil,
        onOpenSheet: (() -> Void)? = nil,
        onFavorite: @escaping () -> Void = {},
        onDownload: @escaping () -> Void = {}
    ) {
        self.isFavorited = isFavorited
        self.isDownloaded = isDownloaded
        self.isDownloading = isDownloading
        self.downloadProgress = downloadProgress
        self.episodesLeft = episodesLeft
        self.onOpenSheet = onOpenSheet
        self.onFavorite = onFavorite
        self.onDownload = onDownload
    }

    private var downloadIconName: String {
        if isDownloaded {
            return "checkmark.circle.fill"
        } else {
            return "arrow.down"
        }
    }

    private var downloadIconTint: Color {
        if isDownloaded || isDownloading {
            return .accentColor
        } else {
            return Color.mainOpp
        }
    }

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                buttonView(
                    item: (
                        systemName: isFavorited ? "star.fill" : "star",
                        action: onFavorite
                    ),
                    tint: isFavorited ? .yellow : Color.mainOpp
                )

                downloadButton
            }
        }
    }

    @ViewBuilder
    private var downloadButton: some View {
        if isDownloading, let episodesLeft, episodesLeft > 0 {
            HStack(spacing: 6) {
                Button(action: onDownload) {
                    ZStack {
                        Circle()
                            .stroke(Color.mainOpp.opacity(0.15), lineWidth: 2.5)
                            .frame(width: 20, height: 20)

                        Circle()
                            .trim(from: 0, to: max(0.04, CGFloat(downloadProgress)))
                            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .frame(width: 20, height: 20)
                            .animation(.smooth(duration: 0.2), value: downloadProgress)

                        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                            .fill(Color.accentColor)
                            .frame(width: 6.5, height: 6.5)
                    }
                    .frame(width: 26, height: 26)
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)

                if let onOpenSheet {
                    Button(action: onOpenSheet) {
                        HStack(spacing: 4) {
                            Text("\(episodesLeft) left")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color.accentColor)

                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .glassEffect(.regular.interactive())
            .glassEffectUnion(id: "trailingButtons", namespace: namespace)
            .accessibilityLabel("Stop Download or view \(episodesLeft) episodes left")
        } else {
            Button(action: onDownload) {
                if isDownloading {
                    ZStack {
                        Circle()
                            .stroke(Color.mainOpp.opacity(0.15), lineWidth: 2.5)
                            .frame(width: 22, height: 22)

                        Circle()
                            .trim(from: 0, to: max(0.04, CGFloat(downloadProgress)))
                            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .frame(width: 22, height: 22)
                            .animation(.smooth(duration: 0.2), value: downloadProgress)

                        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                            .fill(Color.accentColor)
                            .frame(width: 7.5, height: 7.5)
                    }
                    .frame(width: 39, height: 39)
                    .contentShape(Circle())
                } else {
                    Image(systemName: downloadIconName)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(downloadIconTint)
                        .contentTransition(.symbolEffect(.replace))
                        .padding(11) // smaller than BackButton because the default rounded-rect glass hugs content tighter than a Circle
                }
            }
            .glassEffect(.regular.interactive())
            .glassEffectUnion(id: "trailingButtons", namespace: namespace)
            .accessibilityLabel(isDownloading ? "Stop Download" : (isDownloaded ? "Delete Download" : "Download"))
        }
    }

    @ViewBuilder
    private func buttonView(item: ButtonItem, tint: Color) -> some View {
        Button(action: item.action) {
            Image(systemName: item.systemName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tint)
                .contentTransition(.symbolEffect(.replace))
                .padding(11) // smaller than BackButton because the default rounded-rect glass hugs content tighter than a Circle
        }
        .glassEffect(.regular.interactive())
        .glassEffectUnion(id: "trailingButtons", namespace: namespace)
    }
}
