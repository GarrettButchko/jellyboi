//
//  Carousel.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 8/24/26.
//

import SwiftUI
import BaseColors
import SDWebImageSwiftUI
import JellyfinAPI

private let carouselCardWidthRatio: CGFloat = 0.8
private let carouselRestingGap: CGFloat = 0
private let carouselNeighborScale: CGFloat = 0.90
private let carouselAutoScrollInterval: TimeInterval = 9
private let carouselBufferSize: Int = 5
private let carouselMaxItems: Int = 6

struct Carousel: View {
    let title: String
    let namespace: Namespace.ID
    let backdropURL: (BaseItemDto) -> URL?
    let onSelect: (BaseItemDto) -> Void
    var onSnap: ((Int, BaseItemDto) -> Void)? = nil
    @EnvironmentObject var viewModel: HomeViewModel

    private var indexAnimation: Animation {
        .smooth(duration: 0.3)
    }

    @State private var currentIndex: Int? = nil
    @State private var snappedIndex: Int = 0
    @State private var hoveredID: Int? = nil
    @State private var timerResetTrigger: UUID = UUID()
    @State private var isAutoScrolling: Bool = false
    @State private var pendingTeleportTarget: Int? = nil
    @State private var slideStartDate: Date = .now
    @State private var isVisible: Bool = true

    // Top items by most absolute time watched (precomputed once at fetch time)
    private var items: [BaseItemDto] {
        viewModel.topWatchedMovies
    }

    private var buf: Int { min(carouselBufferSize, items.count) }

    private var loopedItems: [(id: Int, item: BaseItemDto)] {
        guard !items.isEmpty else { return [] }
        let count = items.count
        let b = buf
        var result: [(id: Int, item: BaseItemDto)] = []
        for i in 0..<b      { result.append((id: i,             item: items[count - b + i])) }
        for i in 0..<count  { result.append((id: b + i,          item: items[i])) }
        for i in 0..<b      { result.append((id: b + count + i,  item: items[i])) }
        return result
    }

    private var loopStart: Int { buf }

    private func itemIndex(for loopedID: Int) -> Int {
        let count = items.count
        let b = buf
        if loopedID < b            { return count - b + loopedID }
        if loopedID >= b + count   { return loopedID - b - count }
        return loopedID - b
    }

    private var displayedItemIndex: Int {
        items.isEmpty ? 0 : itemIndex(for: snappedIndex)
    }

    var body: some View {
        VStack(spacing: 12) {
            GeometryReader { geometry in
                let cardWidth = geometry.size.width * carouselCardWidthRatio
                let cardHeight = cardWidth * 9 / 16
                let sideInset = (geometry.size.width - cardWidth) / 2

                ScrollViewReader { proxy in
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: carouselRestingGap) {
                            ForEach(loopedItems, id: \.id) { (loopedID, item) in
                                let isRealSection = loopedID >= loopStart && loopedID < loopStart + items.count
                                let baseScale: CGFloat = snappedIndex == loopedID ? 1.0 : carouselNeighborScale
                                let isHovered = hoveredID == loopedID
                                let scale: CGFloat = isHovered ? min(baseScale + 0.05, 1.0) : baseScale
                                CarouselCard(
                                    item: item,
                                    backdropURL: backdropURL,
                                    width: cardWidth,
                                    height: cardHeight
                                )
                                .id(loopedID)
                                .scaleEffect(scale)
                                .brightness(isHovered ? 0.06 : 0)
                                .animation(.easeInOut(duration: 0.2), value: hoveredID)
                                .matchedTransitionSource(
                                    id: isRealSection ? AnyHashable(item) : AnyHashable(loopedID),
                                    in: namespace
                                )
                                .onTapGesture {
                                    if currentIndex == loopedID {
                                        onSelect(item)
                                    } else {
                                        isAutoScrolling = false
                                        
                                        withAnimation(.easeInOut(duration: 0.3)) {
                                            currentIndex = loopedID
                                            proxy.scrollTo(loopedID, anchor: .center)
                                        }
                                    }
                                }
                                .onHover { hovering in
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        hoveredID = hovering ? loopedID : nil
                                    }
                                }
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .contentMargins(.horizontal, sideInset, for: .scrollContent)
                    .scrollTargetBehavior(.viewAligned)
                    .scrollPosition(id: $currentIndex, anchor: .center)
                    .scrollIndicators(.hidden)
                    .frame(height: cardHeight)
                    .onAppear {
                        guard !items.isEmpty else { return }
                        proxy.scrollTo(loopStart, anchor: .center)
                        currentIndex = loopStart
                        snappedIndex = loopStart
                    }
                    .onChange(of: currentIndex) { _, newValue in
                        guard let newValue, newValue != snappedIndex else { return }

                        let count = items.count
                        let b = buf
                        guard count > 0 else { return }

                        withAnimation(indexAnimation) {
                            snappedIndex = newValue
                        }
                        onSnap?(itemIndex(for: newValue), items[itemIndex(for: newValue)])

                        if isAutoScrolling {
                            isAutoScrolling = false
                        } else {
                            timerResetTrigger = UUID()
                        }

                        if newValue < b {
                            pendingTeleportTarget = count + newValue
                        } else if newValue >= b + count {
                            pendingTeleportTarget = newValue - count
                        } else {
                            pendingTeleportTarget = nil
                        }
                    }
                    .onScrollPhaseChange { _, newPhase in
                        guard newPhase == .idle, let target = pendingTeleportTarget else { return }
                        pendingTeleportTarget = nil
                        snappedIndex = target
                        currentIndex = target
                        proxy.scrollTo(target, anchor: .center)
                    }
                    .onChange(of: items.count) { _, newCount in
                        guard newCount > 0 else { return }
                        let start = min(carouselBufferSize, newCount)
                        pendingTeleportTarget = nil
                        snappedIndex = start
                        currentIndex = start
                        proxy.scrollTo(start, anchor: .center)
                        timerResetTrigger = UUID()
                    }
                    .task(id: timerResetTrigger) {
                        slideStartDate = .now
                        while !Task.isCancelled {
                            if !isVisible {
                                try? await Task.sleep(for: .milliseconds(200))
                                continue
                            }
                            try? await Task.sleep(for: .seconds(carouselAutoScrollInterval))
                            guard !Task.isCancelled else { break }
                            guard items.count > 1 else { continue }
                            isAutoScrolling = true
                            let nextIndex = snappedIndex + 1
                            currentIndex = nextIndex //Always Keep this for carousel
                            withAnimation(.easeInOut(duration: 0.4)) {
                                proxy.scrollTo(nextIndex, anchor: .center)
                            }
                            // Restart progress fill for the next slide
                            slideStartDate = .now
                        }
                    }
                }
            }
            .aspectRatio(16 / (9 * carouselCardWidthRatio), contentMode: .fit)
            .frame(maxWidth: .infinity)

            if !items.isEmpty {
                CarouselPageIndicator(
                    count: items.count,
                    currentIndex: displayedItemIndex,
                    startDate: slideStartDate,
                    isPaused: !isVisible
                )
            }
        }
        .onScrollVisibilityChange(threshold: 0.5) { isVisible = $0 }
        .onChange(of: isVisible) { _, visible in
            if visible {
                timerResetTrigger = UUID()
                slideStartDate = .now
            }
        }
        .sensoryFeedback(.selection, trigger: displayedItemIndex)
    }
}

// MARK: - Page Indicator

private struct CarouselPageIndicator: View {
    let count: Int
    let currentIndex: Int
    let startDate: Date
    var isPaused: Bool = false

    private let dotSize: CGFloat = 6
    private let activePillWidth: CGFloat = 20

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<count, id: \.self) { i in
                let isActive = i == currentIndex
                let width = isActive ? activePillWidth : dotSize
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.mainOpp.opacity(0.3))
                        .frame(width: width, height: dotSize)
                    if isActive {
                        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: isPaused)) { context in
                            let progress = min(max(context.date.timeIntervalSince(startDate) / carouselAutoScrollInterval, 0), 1)
                            Canvas { ctx, size in
                                let trackRect = CGRect(origin: .zero, size: size)
                                let radius = size.height / 2
                                ctx.fill(Path(roundedRect: trackRect, cornerRadius: radius), with: .color(Color.mainOpp.opacity(0.3)))
                                guard progress > 0 else { return }
                                let fillRect = CGRect(x: 0, y: 0, width: size.width * progress, height: size.height)
                                ctx.clip(to: Path(roundedRect: fillRect, cornerRadius: radius))
                                ctx.fill(Path(roundedRect: trackRect, cornerRadius: radius), with: .color(Color.mainOpp))
                            }
                        }
                        .frame(width: width, height: dotSize)
                    }
                }
                .frame(width: width, height: dotSize)
                .animation(.smooth(duration: 0.25), value: isActive)
            }
        }
    }
}

// MARK: - Card

private struct CarouselCard: View {
    let item: BaseItemDto
    let backdropURL: (BaseItemDto) -> URL?
    let width: CGFloat
    let height: CGFloat

    private let outerCornerRadius: CGFloat = 20

    private var watchProgress: Double? {
        guard let percent = item.userData?.playedPercentage,
              percent > 0, percent < 85 else { return nil }
        return min(max(percent / 100, 0), 1)
    }

    private var timeRemainingLabel: String? {
        guard let ticks = item.runTimeTicks,
              let percent = item.userData?.playedPercentage,
              percent > 0 else { return nil }
        let totalSeconds = Int(ticks / 10_000_000)
        let remainingSeconds = totalSeconds - Int(Double(totalSeconds) * percent / 100)
        guard remainingSeconds > 60 else { return nil }
        let hours = remainingSeconds / 3600
        let minutes = (remainingSeconds % 3600) / 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            backdropImage
            LinearGradient(
                colors: [.clear, .black.opacity(0.5)],
                startPoint: .center,
                endPoint: .bottom
            )
            if let progress = watchProgress {
                GlassProgressBar(progress: progress, label: timeRemainingLabel)
                    .padding(10)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: outerCornerRadius, style: .continuous))
        .clipped()
    }

    @ViewBuilder
    private var backdropImage: some View {
        if let url = backdropURL(item) {
            WebImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Color.sub
            }
            .frame(width: width, height: height)
        } else {
            Color.sub
                .frame(width: width, height: height)
        }
    }
}
