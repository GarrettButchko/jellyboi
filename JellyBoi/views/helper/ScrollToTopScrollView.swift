//
//  ScrollToTopScrollView.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 10/16/26.
//

import SwiftUI

/// Discrete equatable state for scrolling thresholds.
/// This prevents continuous per-frame re-evaluations and frame drops.
public struct ScrollToTopScrollState: Equatable, Sendable {
    public var showTitle: Bool
    public var showBottomBar: Bool

    public var isHeaderCollapsed: Bool { showTitle }
    public var showScrollToTop: Bool { showBottomBar }

    public init(
        showTitle: Bool = false,
        showBottomBar: Bool = false
    ) {
        self.showTitle = showTitle
        self.showBottomBar = showBottomBar
    }
}

@Observable
@MainActor
private final class ScrollStateCoordinator {
    var showTitle: Bool = false
    var showBottomBar: Bool = false
}

private struct HeaderContainer<Header: View>: View {
    let coordinator: ScrollStateCoordinator
    @ViewBuilder let header: (Bool) -> Header

    var body: some View {
        header(coordinator.showTitle)
    }
}

/// Renders the overlay locally for hosts that don't provide a
/// `ScrollOverlayCoordinator` (previews, or screens presented outside the tab
/// view). Inside the tab view the overlay lives in the tab bar accessory.
private struct ScrollOverlayContainer: View {
    let coordinator: ScrollStateCoordinator
    let onScrollToTop: () -> Void

    var body: some View {
        ScrollTabBarOverlay(
            isVisible: coordinator.showBottomBar,
            action: onScrollToTop
        )
        .safeAreaPadding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }
}

/// A reusable `ScrollView` wrapper that integrates a floating "Top" scroll-to-top button,
/// tracks discrete scroll thresholds to prevent 120Hz view re-renders and frame drops,
/// handles dynamic content insets for headers and the floating button,
/// and provides programmatic scroll-to-top support via `ScrollPosition`.
public struct ScrollToTopScrollView<Content: View, Header: View>: View {
    private static var titleCollapseThreshold: CGFloat { 40 }
    private static var bottomBarThreshold: CGFloat { 300 }

    private let topInset: CGFloat
    private let bottomInset: CGFloat
    private let header: (Bool) -> Header
    private let content: () -> Content

    private var externalPosition: Binding<ScrollPosition>?

    @State private var internalPosition = ScrollPosition()
    @State private var coordinator = ScrollStateCoordinator()
    @State private var overlaySourceID = UUID()

    @Environment(ScrollOverlayCoordinator.self) private var overlayCoordinator: ScrollOverlayCoordinator?

    private var effectivePosition: Binding<ScrollPosition> {
        externalPosition ?? $internalPosition
    }

    private func scrollToTop() {
        withAnimation {
            effectivePosition.wrappedValue.scrollTo(edge: .top)
        }
    }

    public init(
        position: Binding<ScrollPosition>? = nil,
        topInset: CGFloat = 0,
        bottomInset: CGFloat = 16,
        @ViewBuilder header: @escaping (_ showTitle: Bool) -> Header,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.externalPosition = position
        self.topInset = topInset
        self.bottomInset = bottomInset
        self.header = header
        self.content = content
    }

    public init(
        position: Binding<ScrollPosition>? = nil,
        topInset: CGFloat = 0,
        bottomInset: CGFloat = 16,
        @ViewBuilder header: @escaping () -> Header,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(
            position: position,
            topInset: topInset,
            bottomInset: bottomInset,
            header: { _ in header() },
            content: content
        )
    }

    public var body: some View {
        ZStack(alignment: .top) {
            ScrollView(.vertical, showsIndicators: true) {
                content()
            }
            .scrollPosition(effectivePosition)
            .contentMargins(.top, topInset, for: .scrollContent)
            .contentMargins(.bottom, 48 + bottomInset, for: .scrollContent)
            // Discrete Equatable geometry change: SwiftUI only calls action when Equatable newState != oldState!
            .onScrollGeometryChange(for: ScrollToTopScrollState.self) { geometry in
                let offset = geometry.contentOffset.y + geometry.contentInsets.top
                return ScrollToTopScrollState(
                    showTitle: offset > Self.titleCollapseThreshold,
                    showBottomBar: offset > Self.bottomBarThreshold
                )
            } action: { _, newState in
                if coordinator.showTitle != newState.showTitle {
                    coordinator.showTitle = newState.showTitle
                }
                if coordinator.showBottomBar != newState.showBottomBar {
                    coordinator.showBottomBar = newState.showBottomBar
                    overlayCoordinator?.updateScrollToTopVisibility(
                        newState.showBottomBar,
                        for: overlaySourceID
                    )
                }
            }

            HeaderContainer(coordinator: coordinator, header: header)

            // The tab view owns the overlay through its bottom accessory and
            // renders a single instance for every tab. Only draw it locally
            // when no shared coordinator is available.
            if overlayCoordinator == nil {
                ScrollOverlayContainer(coordinator: coordinator, onScrollToTop: scrollToTop)
            }
        }
        .onAppear {
            overlayCoordinator?.activate(
                overlaySourceID,
                isScrollToTopVisible: coordinator.showBottomBar,
                scrollToTop: scrollToTop
            )
        }
        .onDisappear {
            overlayCoordinator?.deactivate(overlaySourceID)
        }
    }
}

// MARK: - Initializers without Header

extension ScrollToTopScrollView where Header == EmptyView {
    public init(
        position: Binding<ScrollPosition>? = nil,
        topInset: CGFloat = 0,
        bottomInset: CGFloat = 16,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(
            position: position,
            topInset: topInset,
            bottomInset: bottomInset,
            header: { _ in EmptyView() },
            content: content
        )
    }
}

// MARK: - ScrollPosition Extension

extension ScrollPosition {
    /// Scrolls to the top edge of the scroll view.
    public mutating func scrollToTop() {
        scrollTo(edge: .top)
    }
}
