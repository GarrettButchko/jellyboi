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
private let carouselRestingGap: CGFloat = 40

struct Carousel: View {
    let title: String
    let items: [BaseItemDto]
    let namespace: Namespace.ID
    let isInteractive: Bool
    let backdropURL: (BaseItemDto) -> URL?
    let onSelect: (BaseItemDto) -> Void

    @State private var currentIndex = 0
    @State private var dragOffset: CGFloat = 0
    @State private var isAnimating = false

    var body: some View {
        VStack(alignment: .center, spacing: 12) {
            GeometryReader { geometry in
                let cardWidth = geometry.size.width * carouselCardWidthRatio
                let cardHeight = cardWidth * 9 / 16
                // 0.95 = half of full card + half of scaled neighbor, so the resting edge gap is constant
                let pitch = cardWidth + carouselRestingGap

                ZStack {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        // Only materialize the visible trio for smooth scrolling with big libraries
                        if abs(index - currentIndex) <= 1{
                            let distance = cardDistance(index: index, pitch: pitch)

                            CarouselCard(
                                item: item,
                                backdropURL: backdropURL,
                                width: cardWidth,
                                height: cardHeight
                            )
                            .offset(x: CGFloat(index - currentIndex) * pitch + dragOffset)
                            .scaleEffect(1.0 - 0.2 * max(distance - 0.5, 0))
                            .zIndex(distance < 0.5 ? 1 : 0)
                            .matchedTransitionSource(id: item, in: namespace)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .highPriorityGesture(swipeGesture(width: geometry.size.width))
            }
            // Height = width * cardRatio * 9/16, expressed as an aspect ratio (width:height)
            .aspectRatio(16 / (9 * carouselCardWidthRatio), contentMode: .fit)
        }
        .onChange(of: items.count) { _, newCount in
            currentIndex = min(max(currentIndex, 0), max(newCount - 1, 0))
        }
        .frame(maxWidth: .infinity)
    }

    private func swipeGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard isInteractive, !isAnimating else { return }
                dragOffset = value.translation.width
            }
            .onEnded { value in
                guard isInteractive, !isAnimating else {
                    withAnimation(.smooth(duration: 0.3)) { dragOffset = 0 }
                    return
                }
                let translation = value.translation.width

                // Small movement = tap on the center card
                if abs(translation) < 5 && abs(value.translation.height) < 5 {
                    onSelect(items[currentIndex])
                    dragOffset = 0
                    return
                }

                let threshold = width * 0.1
                isAnimating = true
                withAnimation(.smooth(duration: 0.3)) {
                    if translation < -threshold && currentIndex < items.count - 1 {
                        currentIndex += 1
                    } else if translation > threshold && currentIndex > 0 {
                        currentIndex -= 1
                    }
                    dragOffset = 0
                } completion: {
                    isAnimating = false
                }
            }
    }

    private func cardDistance(index: Int, pitch: CGFloat) -> CGFloat {
        abs(CGFloat(index - currentIndex) * pitch + dragOffset) / pitch
    }
}

// MARK: - Card

private struct CarouselCard: View {
    let item: BaseItemDto
    let backdropURL: (BaseItemDto) -> URL?
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        ZStack(alignment: .bottom) {
            backdropImage
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .clipped()
    }

    private var watchProgress: Double? {
        if item.userData?.isPlayed == true { return 1 }
        guard let percent = item.userData?.playedPercentage else { return nil }
        return min(max(percent / 100, 0), 1)
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

    private func progressBar(_ progress: Double) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Color.main.opacity(0.4)
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.main)
                    .frame(width: proxy.size.width * progress)
            }
        }
        .frame(height: 6)
    }
}
