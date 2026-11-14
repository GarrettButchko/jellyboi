//
//  ScrollTabBarOverlay.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 10/23/26.
//

import SwiftUI
import Observation

/// Shared state that lets a single `ScrollTabBarOverlay` live at the tab bar
/// level instead of inside every individual scroll view.
///
/// Each `ScrollToTopScrollView` registers itself as the active source when it
/// appears, reports its discrete scroll state, and unregisters when it goes
/// away. The tab view's bottom accessory renders one overlay from that state.
@Observable
@MainActor
final class ScrollOverlayCoordinator {
    /// Whether the active scroll source is scrolled far enough to show the
    /// scroll-to-top button.
    private(set) var isScrollToTopVisible: Bool = false

    /// Identifier of the scroll view that currently owns the overlay.
    private(set) var activeSourceID: UUID?

    @ObservationIgnored
    private var scrollToTopAction: (() -> Void)?

    /// Makes `id` the active scroll source, restoring the visibility it had
    /// before it went off screen (for example after popping a detail view).
    func activate(
        _ id: UUID,
        isScrollToTopVisible: Bool,
        scrollToTop: @escaping () -> Void
    ) {
        activeSourceID = id
        scrollToTopAction = scrollToTop
        self.isScrollToTopVisible = isScrollToTopVisible
    }

    /// Updates visibility only when the reporting view is still the active one.
    func updateScrollToTopVisibility(_ isVisible: Bool, for id: UUID) {
        guard activeSourceID == id else { return }
        isScrollToTopVisible = isVisible
    }

    func deactivate(_ id: UUID) {
        guard activeSourceID == id else { return }
        activeSourceID = nil
        scrollToTopAction = nil
        isScrollToTopVisible = false
    }

    func scrollToTop() {
        scrollToTopAction?()
    }
}

/// Floating overlay rendered as the tab view's bottom accessory, directly
/// above the tab bar. Shows the active download bar and, once the current
/// screen is scrolled past the threshold, a scroll-to-top button.
struct ScrollTabBarOverlay: View {
    let isVisible: Bool
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

    var body: some View {
        // Resolved once per update instead of once per reference below: this overlay sits above
        // every tab, so it re-evaluates on every download progress tick.
        let active = downloadManager.activeDownloads
        let presentation = downloadManager.currentPresentation
        let hasActiveDownloads = !active.isEmpty

        ZStack(alignment: .bottom) {
            if hasActiveDownloads {
                HStack(spacing: 8) {
                    ActiveDownloadFloatingBar(
                        presentation: presentation,
                        activeDownloads: active
                    ) {
                        if let single = singleGroup {
                            activeSheetTarget = .group(id: single.id, name: single.name)
                        } else {
                            activeSheetTarget = .main
                        }
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))

                    if isVisible {
                        CircleScrollToTopButton(action: action)
                            .transition(.scale(scale: 0.6).combined(with: .opacity))
                    }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.spring(response: 0.38, dampingFraction: 0.78), value: isVisible)
                .animation(.spring(response: 0.38, dampingFraction: 0.78), value: active.count > 1)
                .animation(.spring(response: 0.38, dampingFraction: 0.78), value: active.count)
            } else if isVisible {
                ScrollToTopButton(action: action)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .allowsHitTesting(hasActiveDownloads || isVisible)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isVisible)
        .animation(.spring(response: 0.38, dampingFraction: 0.78), value: hasActiveDownloads)
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
