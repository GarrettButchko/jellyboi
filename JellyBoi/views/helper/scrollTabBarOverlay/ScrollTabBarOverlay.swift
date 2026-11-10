//
//  ScrollTabBarOverlay.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 10/23/26.
//

import SwiftUI

/// Floating overlay that sits over a scroll view and appears once the user
/// has scrolled past `threshold` points. Animates in from the bottom with
/// smooth opacity/scale transitions without tearing down views mid-scroll.
struct ScrollTabBarOverlay: View {
    let isVisible: Bool
    var threshold: CGFloat = 300
    @Binding var STTButtonHeight: CGFloat
    let action: () -> Void
    @Environment(DownloadManager.self) private var downloadManager

    private enum ActiveDownloadsSheetTarget: Identifiable {
        case main
        case group(id: String, name: String)

        var id: String {
            switch self {
            case .main: return "main"
            case .group(let id, _): return "group-\(id)"
            }
        }
    }

    @State private var activeSheetTarget: ActiveDownloadsSheetTarget?

    private var singleGroup: (id: String, name: String)? {
        let active = downloadManager.activeDownloads
        guard !active.isEmpty else { return nil }
        let groups = DownloadGrouping.groups(from: active, completed: downloadManager.completedDownloads)
        let standalone = DownloadGrouping.standaloneDownloads(from: active, groupedIDs: Set(groups.map(\.id)))
        if groups.count == 1 && standalone.isEmpty, let group = groups.first {
            return (id: group.id, name: group.seriesName)
        }
        return nil
    }

    init(
        scrollOffset: CGFloat,
        threshold: CGFloat = 300,
        STTButtonHeight: Binding<CGFloat>,
        action: @escaping () -> Void
    ) {
        self.isVisible = scrollOffset > threshold
        self.threshold = threshold
        self._STTButtonHeight = STTButtonHeight
        self.action = action
    }

    init(
        isVisible: Bool,
        threshold: CGFloat = 300,
        STTButtonHeight: Binding<CGFloat>,
        action: @escaping () -> Void
    ) {
        self.isVisible = isVisible
        self.threshold = threshold
        self._STTButtonHeight = STTButtonHeight
        self.action = action
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            if !downloadManager.activeDownloads.isEmpty {
                HStack(spacing: 8) {
                    ActiveDownloadFloatingBar(
                        presentation: downloadManager.currentPresentation,
                        activeDownloads: downloadManager.activeDownloads
                    ) {
                        if let single = singleGroup {
                            activeSheetTarget = .group(id: single.id, name: single.name)
                        } else {
                            activeSheetTarget = .main
                        }
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))

                    CircleScrollToTopButton(action: action)
                        .opacity(isVisible ? 1.0 : 0.0)
                        .scaleEffect(isVisible ? 1.0 : 0.6)
                        .allowsHitTesting(isVisible)
                }
                .padding(.bottom, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.spring(response: 0.38, dampingFraction: 0.78), value: isVisible)
                .animation(.spring(response: 0.38, dampingFraction: 0.78), value: downloadManager.activeDownloads.count > 1)
                .animation(.spring(response: 0.38, dampingFraction: 0.78), value: downloadManager.activeDownloads.count)
            } else {
                ScrollToTopButton(action: action)
                    .padding(.bottom, 8)
                    .opacity(isVisible ? 1.0 : 0.0)
                    .offset(y: isVisible ? 0 : 20)
                    .scaleEffect(isVisible ? 1.0 : 0.8)
                    .allowsHitTesting(isVisible)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .allowsHitTesting(!downloadManager.activeDownloads.isEmpty || isVisible)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isVisible)
        .animation(.spring(response: 0.38, dampingFraction: 0.78), value: !downloadManager.activeDownloads.isEmpty)
        .sheet(item: $activeSheetTarget) { target in
            switch target {
            case .main:
                DownloadsSheet()
            case .group(let id, let name):
                DownloadsSheet(seriesID: id, seriesName: name)
            }
        }
    }
}
