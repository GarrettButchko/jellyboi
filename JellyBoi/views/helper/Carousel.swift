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
private let carouselRestingGap: CGFloat = 5
private let carouselNeighborScale: CGFloat = 0.85

struct Carousel: View {
    let title: String
    let namespace: Namespace.ID
    let backdropURL: (BaseItemDto) -> URL?
    let onSelect: (BaseItemDto) -> Void
    @EnvironmentObject var viewModel: HomeViewModel

    @State private var currentIndex: Int? = 0
    @State private var snappedIndex: Int = 0

    var body: some View {
        GeometryReader { geometry in
            let cardWidth = geometry.size.width * carouselCardWidthRatio
            let cardHeight = cardWidth * 9 / 16
            let sideInset = (geometry.size.width - cardWidth) / 2

            ScrollView(.horizontal) {
                LazyHStack(spacing: carouselRestingGap) {
                    ForEach(Array(viewModel.movies.enumerated()), id: \.element.id) { index, item in
                        let scale: CGFloat = snappedIndex == index ? 1.0 : carouselNeighborScale
                        CarouselCard(
                            item: item,
                            backdropURL: backdropURL,
                            width: cardWidth * scale,
                            height: cardHeight * scale
                        )
                        .animation(.smooth(duration: 0.3), value: snappedIndex == index)
                        .id(index)
                        .matchedTransitionSource(id: item, in: namespace)
                        .onTapGesture {
                            if currentIndex == index {
                                onSelect(item)
                            } else {
                                withAnimation { currentIndex = index }
                            }
                        }
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, sideInset)
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $currentIndex)
            .scrollIndicators(.hidden)
            .frame(height: cardHeight)
        }
        .aspectRatio(16 / (9 * carouselCardWidthRatio), contentMode: .fit)
        .sensoryFeedback(.selection, trigger: snappedIndex)
        .onChange(of: currentIndex) { _, newIndex in
            guard let newIndex, newIndex != snappedIndex else { return }
            snappedIndex = newIndex
        }
        .onChange(of: viewModel.movies.count) { _, newCount in
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
