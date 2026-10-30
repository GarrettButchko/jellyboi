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
    public var isPastTop: Bool
    public var isHeaderCollapsed: Bool
    public var showScrollToTop: Bool

    public init(
        isPastTop: Bool = false,
        isHeaderCollapsed: Bool = false,
        showScrollToTop: Bool = false
    ) {
        self.isPastTop = isPastTop
        self.isHeaderCollapsed = isHeaderCollapsed
        self.showScrollToTop = showScrollToTop
    }
}

/// A reusable `ScrollView` wrapper that integrates a floating "Top" scroll-to-top button,
/// tracks discrete scroll thresholds to prevent 120Hz view re-renders and frame drops,
/// handles dynamic content insets for headers and the floating button,
/// and provides programmatic scroll-to-top support.
public struct ScrollToTopScrollView<Content: View, Header: View>: View {
    public static var topAnchorID: String { "ScrollToTopScrollView_topAnchor" }

    private let axes: Axis.Set
    private let showsIndicators: Bool
    private let threshold: CGFloat
    private let headerCollapseThreshold: CGFloat
    private let topInset: CGFloat
    private var bottomInset: CGFloat = 16
    private let showsScrollToTop: Bool
    private let scrollToTopTrigger: Binding<Bool>?
    private let isHeaderCollapsedBinding: Binding<Bool>?
    private let scrollStateBinding: Binding<ScrollToTopScrollState>?
    private let continuousScrollOffsetBinding: Binding<CGFloat>?
    @Binding private var scrollOffset: CGFloat
    private let onScrollStateChange: ((ScrollToTopScrollState) -> Void)?
    private let header: (Bool) -> Header
    private let content: (ScrollViewProxy) -> Content

    @State private var scrollState = ScrollToTopScrollState()
    @State private var sttButtonHeight: CGFloat = 0

    public init(
        _ axes: Axis.Set = .vertical,
        showsIndicators: Bool = true,
        threshold: CGFloat = 300,
        headerCollapseThreshold: CGFloat = 40,
        topInset: CGFloat = 0,
        bottomInset: CGFloat = 16,
        showsScrollToTop: Bool = true,
        isHeaderCollapsed: Binding<Bool>? = nil,
        scrollState: Binding<ScrollToTopScrollState>? = nil,
        scrollOffset: Binding<CGFloat>? = nil,
        continuousScrollOffset: Binding<CGFloat>? = nil,
        scrollToTop: Binding<Bool>? = nil,
        onScrollStateChange: ((ScrollToTopScrollState) -> Void)? = nil,
        @ViewBuilder header: @escaping (_ isHeaderCollapsed: Bool) -> Header,
        @ViewBuilder content: @escaping (ScrollViewProxy) -> Content
    ) {
        self.axes = axes
        self.showsIndicators = showsIndicators
        self.threshold = threshold
        self.headerCollapseThreshold = headerCollapseThreshold
        self.topInset = topInset
        self.bottomInset = bottomInset
        self.showsScrollToTop = showsScrollToTop
        self.isHeaderCollapsedBinding = isHeaderCollapsed
        self.scrollStateBinding = scrollState
        self.continuousScrollOffsetBinding = continuousScrollOffset
        self._scrollOffset = scrollOffset ?? .constant(0)
        self.scrollToTopTrigger = scrollToTop
        self.onScrollStateChange = onScrollStateChange
        self.header = header
        self.content = content
    }

    public init(
        _ axes: Axis.Set = .vertical,
        showsIndicators: Bool = true,
        threshold: CGFloat = 300,
        headerCollapseThreshold: CGFloat = 40,
        topInset: CGFloat = 0,
        bottomInset: CGFloat = 16,
        showsScrollToTop: Bool = true,
        isHeaderCollapsed: Binding<Bool>? = nil,
        scrollState: Binding<ScrollToTopScrollState>? = nil,
        scrollOffset: Binding<CGFloat>? = nil,
        continuousScrollOffset: Binding<CGFloat>? = nil,
        scrollToTop: Binding<Bool>? = nil,
        onScrollStateChange: ((ScrollToTopScrollState) -> Void)? = nil,
        @ViewBuilder header: @escaping () -> Header,
        @ViewBuilder content: @escaping (ScrollViewProxy) -> Content
    ) {
        self.init(
            axes,
            showsIndicators: showsIndicators,
            threshold: threshold,
            headerCollapseThreshold: headerCollapseThreshold,
            topInset: topInset,
            bottomInset: bottomInset,
            showsScrollToTop: showsScrollToTop,
            isHeaderCollapsed: isHeaderCollapsed,
            scrollState: scrollState,
            scrollOffset: scrollOffset,
            continuousScrollOffset: continuousScrollOffset,
            scrollToTop: scrollToTop,
            onScrollStateChange: onScrollStateChange,
            header: { _ in header() },
            content: content
        )
    }

    public init(
        _ axes: Axis.Set = .vertical,
        showsIndicators: Bool = true,
        threshold: CGFloat = 300,
        headerCollapseThreshold: CGFloat = 40,
        topInset: CGFloat = 0,
        bottomInset: CGFloat = 16,
        showsScrollToTop: Bool = true,
        isHeaderCollapsed: Binding<Bool>? = nil,
        scrollState: Binding<ScrollToTopScrollState>? = nil,
        scrollOffset: Binding<CGFloat>? = nil,
        continuousScrollOffset: Binding<CGFloat>? = nil,
        scrollToTop: Binding<Bool>? = nil,
        onScrollStateChange: ((ScrollToTopScrollState) -> Void)? = nil,
        @ViewBuilder header: @escaping (_ isHeaderCollapsed: Bool) -> Header,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(
            axes,
            showsIndicators: showsIndicators,
            threshold: threshold,
            headerCollapseThreshold: headerCollapseThreshold,
            topInset: topInset,
            bottomInset: bottomInset,
            showsScrollToTop: showsScrollToTop,
            isHeaderCollapsed: isHeaderCollapsed,
            scrollState: scrollState,
            scrollOffset: scrollOffset,
            continuousScrollOffset: continuousScrollOffset,
            scrollToTop: scrollToTop,
            onScrollStateChange: onScrollStateChange,
            header: header
        ) { _ in content() }
    }

    public init(
        _ axes: Axis.Set = .vertical,
        showsIndicators: Bool = true,
        threshold: CGFloat = 300,
        headerCollapseThreshold: CGFloat = 40,
        topInset: CGFloat = 0,
        bottomInset: CGFloat = 16,
        showsScrollToTop: Bool = true,
        isHeaderCollapsed: Binding<Bool>? = nil,
        scrollState: Binding<ScrollToTopScrollState>? = nil,
        scrollOffset: Binding<CGFloat>? = nil,
        continuousScrollOffset: Binding<CGFloat>? = nil,
        scrollToTop: Binding<Bool>? = nil,
        onScrollStateChange: ((ScrollToTopScrollState) -> Void)? = nil,
        @ViewBuilder header: @escaping () -> Header,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(
            axes,
            showsIndicators: showsIndicators,
            threshold: threshold,
            headerCollapseThreshold: headerCollapseThreshold,
            topInset: topInset,
            bottomInset: bottomInset,
            showsScrollToTop: showsScrollToTop,
            isHeaderCollapsed: isHeaderCollapsed,
            scrollState: scrollState,
            scrollOffset: scrollOffset,
            continuousScrollOffset: continuousScrollOffset,
            scrollToTop: scrollToTop,
            onScrollStateChange: onScrollStateChange,
            header: header
        ) { _ in content() }
    }

    public var body: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .top) {
                ScrollView(axes, showsIndicators: showsIndicators) {
                    Color.clear
                        .frame(height: 0)
                        .id(Self.topAnchorID)

                    content(proxy)
                }
                .contentMargins(.top, topInset, for: .scrollContent)
                .contentMargins(.bottom, (showsScrollToTop ? 48 : 0) + bottomInset, for: .scrollContent)
                .scrollEdgeEffectHidden(!scrollState.isPastTop, for: .top)
                // Discrete Equatable geometry change: SwiftUI only calls action when Equatable newState != oldState!
                .onScrollGeometryChange(for: ScrollToTopScrollState.self) { geometry in
                    let offset = geometry.contentOffset.y + geometry.contentInsets.top
                    return ScrollToTopScrollState(
                        isPastTop: offset > 0,
                        isHeaderCollapsed: offset > headerCollapseThreshold,
                        showScrollToTop: offset > threshold
                    )
                } action: { _, newState in
                    scrollState = newState
                    isHeaderCollapsedBinding?.wrappedValue = newState.isHeaderCollapsed
                    scrollStateBinding?.wrappedValue = newState
                    // Provides discrete 100 / 0 for TabPageHeader without continuous 120Hz invalidations
                    scrollOffset = newState.isHeaderCollapsed ? 100 : 0
                    onScrollStateChange?(newState)
                }
                .modifier(ContinuousScrollOffsetModifier(binding: continuousScrollOffsetBinding))

                header(scrollState.isHeaderCollapsed)

                if showsScrollToTop {
                    ScrollTabBarOverlay(isVisible: scrollState.showScrollToTop, threshold: threshold, STTButtonHeight: $sttButtonHeight) {
                        withAnimation {
                            proxy.scrollTo(Self.topAnchorID, anchor: .top)
                        }
                    }
                }
            }
            .onChange(of: scrollToTopTrigger?.wrappedValue) { _, shouldScroll in
                if shouldScroll == true {
                    withAnimation {
                        proxy.scrollTo(Self.topAnchorID, anchor: .top)
                    }
                    scrollToTopTrigger?.wrappedValue = false
                }
            }
        }
    }
}

// MARK: - Optional Continuous Modifier

private struct ContinuousScrollOffsetModifier: ViewModifier {
    let binding: Binding<CGFloat>?

    func body(content: Content) -> some View {
        if let binding {
            content.onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top
            } action: { _, newValue in
                binding.wrappedValue = newValue
            }
        } else {
            content
        }
    }
}

// MARK: - Initializers without Header

extension ScrollToTopScrollView where Header == EmptyView {
    public init(
        _ axes: Axis.Set = .vertical,
        showsIndicators: Bool = true,
        threshold: CGFloat = 300,
        headerCollapseThreshold: CGFloat = 40,
        topInset: CGFloat = 0,
        bottomInset: CGFloat = 16,
        showsScrollToTop: Bool = true,
        isHeaderCollapsed: Binding<Bool>? = nil,
        scrollState: Binding<ScrollToTopScrollState>? = nil,
        scrollOffset: Binding<CGFloat>? = nil,
        continuousScrollOffset: Binding<CGFloat>? = nil,
        scrollToTop: Binding<Bool>? = nil,
        onScrollStateChange: ((ScrollToTopScrollState) -> Void)? = nil,
        @ViewBuilder content: @escaping (ScrollViewProxy) -> Content
    ) {
        self.init(
            axes,
            showsIndicators: showsIndicators,
            threshold: threshold,
            headerCollapseThreshold: headerCollapseThreshold,
            topInset: topInset,
            bottomInset: bottomInset,
            showsScrollToTop: showsScrollToTop,
            isHeaderCollapsed: isHeaderCollapsed,
            scrollState: scrollState,
            scrollOffset: scrollOffset,
            continuousScrollOffset: continuousScrollOffset,
            scrollToTop: scrollToTop,
            onScrollStateChange: onScrollStateChange,
            header: { EmptyView() },
            content: content
        )
    }

    public init(
        _ axes: Axis.Set = .vertical,
        showsIndicators: Bool = true,
        threshold: CGFloat = 300,
        headerCollapseThreshold: CGFloat = 40,
        topInset: CGFloat = 0,
        bottomInset: CGFloat = 16,
        showsScrollToTop: Bool = true,
        isHeaderCollapsed: Binding<Bool>? = nil,
        scrollState: Binding<ScrollToTopScrollState>? = nil,
        scrollOffset: Binding<CGFloat>? = nil,
        continuousScrollOffset: Binding<CGFloat>? = nil,
        scrollToTop: Binding<Bool>? = nil,
        onScrollStateChange: ((ScrollToTopScrollState) -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(
            axes,
            showsIndicators: showsIndicators,
            threshold: threshold,
            headerCollapseThreshold: headerCollapseThreshold,
            topInset: topInset,
            bottomInset: bottomInset,
            showsScrollToTop: showsScrollToTop,
            isHeaderCollapsed: isHeaderCollapsed,
            scrollState: scrollState,
            scrollOffset: scrollOffset,
            continuousScrollOffset: continuousScrollOffset,
            scrollToTop: scrollToTop,
            onScrollStateChange: onScrollStateChange
        ) { _ in content() }
    }
}

// MARK: - ScrollViewProxy Extension

extension ScrollViewProxy {
    /// Scrolls to the top anchor of an enclosing `ScrollToTopScrollView`.
    public func scrollToTop(anchor: UnitPoint = .top) {
        scrollTo(ScrollToTopScrollView<EmptyView, EmptyView>.topAnchorID, anchor: anchor)
    }
}
