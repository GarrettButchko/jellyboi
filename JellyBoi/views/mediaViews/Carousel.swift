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
private let carouselAutoScrollInterval: TimeInterval = 5

struct Carousel: View {
    let title: String
    let namespace: Namespace.ID
    let backdropURL: (BaseItemDto) -> URL?
    let onSelect: (BaseItemDto) -> Void
    var onSnap: ((Int, BaseItemDto) -> Void)? = nil
    @EnvironmentObject var viewModel: HomeViewModel

    @State private var currentIndex: Int? = 0
    @State private var snappedIndex: Int = 0
    @State private var timerResetTrigger: UUID = UUID()
    @State private var isAutoScrolling: Bool = false

    var body: some View {
        GeometryReader { geometry in
            let cardWidth = geometry.size.width * carouselCardWidthRatio
            let cardHeight = cardWidth * 9 / 16
            let sideInset = (geometry.size.width - cardWidth) / 2

            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    LazyHStack(spacing: carouselRestingGap) {
                        ForEach(Array(viewModel.inProgressMovies.enumerated()), id: \.element.id) { index, item in
                            let scale: CGFloat = snappedIndex == index ? 1.0 : carouselNeighborScale
                            CarouselCard(
                                item: item,
                                backdropURL: backdropURL,
                                width: cardWidth,
                                height: cardHeight
                            )
                            .id(index)
                            .scaleEffect(scale)
                            .animation(.smooth(duration: 0.3), value: snappedIndex == index)
                            .matchedTransitionSource(id: item, in: namespace)
                            .onTapGesture {
                                guard currentIndex == index else { return }
                                onSelect(item)
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
                .task(id: timerResetTrigger) {
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(carouselAutoScrollInterval))
                        guard !Task.isCancelled else { break }
                        let count = viewModel.inProgressMovies.count
                        guard count > 1 else { continue }
                        isAutoScrolling = true
                        let nextIndex = (snappedIndex + 1) % count
                        currentIndex = nextIndex
                        withAnimation(.easeInOut(duration: 0.4)) {
                            proxy.scrollTo(nextIndex, anchor: .center)
                        }
                    }
                }
            }
        }
        .aspectRatio(16 / (9 * carouselCardWidthRatio), contentMode: .fit)
        .sensoryFeedback(.selection, trigger: snappedIndex)
        .onChange(of: currentIndex) { _, newIndex in
            guard let newIndex, newIndex != snappedIndex else { return }
            snappedIndex = newIndex
            if isAutoScrolling {
                isAutoScrolling = false
            } else {
                timerResetTrigger = UUID()
            }
            let items = viewModel.inProgressMovies
            if newIndex < items.count {
                onSnap?(newIndex, items[newIndex])
            }
        }
        .onChange(of: viewModel.inProgressMovies.count) { _, newCount in
            if let idx = currentIndex {
                currentIndex = min(max(idx, 0), max(newCount - 1, 0))
            }
        }
        .frame(maxWidth: .infinity)
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
