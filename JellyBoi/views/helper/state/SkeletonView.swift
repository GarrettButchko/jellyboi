//
//  SkeletonView.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 8/28/26.
//

import SwiftUI
import BaseColors
import JellyfinAPI

// MARK: - Skeleton Shimmer Modifier

struct SkeletonModifier: ViewModifier {
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .redacted(reason: .placeholder)
            .overlay {
                GeometryReader { geometry in
                    let width = geometry.size.width
                    LinearGradient(
                        colors: [
                            Color.clear,
                            Color.white.opacity(0.12),
                            Color.clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: width * 1.5)
                    .offset(x: phase * width * 2)
                }
                .mask(content)
            }
            .onAppear {
                withAnimation(
                    .linear(duration: 1.6)
                    .repeatForever(autoreverses: false)
                ) {
                    phase = 1
                }
            }
    }
}

extension View {
    /// Applies a shimmering placeholder skeleton effect to the view.
    func skeleton() -> some View {
        modifier(SkeletonModifier())
    }
}

// MARK: - Primitive Skeleton Shapes

struct SkeletonBlock: View {
    var cornerRadius: CGFloat = 8

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.mainOpp.opacity(0.08))
            .skeleton()
    }
}

struct SkeletonCircle: View {
    var diameter: CGFloat = 40

    var body: some View {
        Circle()
            .fill(Color.mainOpp.opacity(0.08))
            .frame(width: diameter, height: diameter)
            .skeleton()
    }
}

// MARK: - Media Skeleton Components

struct MediaCardSkeleton: View {
    var aspectRatio: CGFloat = MediaAspectRatio.poster

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SkeletonBlock(cornerRadius: 10)
                .aspectRatio(aspectRatio, contentMode: .fit)

            SkeletonBlock(cornerRadius: 4)
                .frame(height: 12)
                .frame(maxWidth: .infinity, alignment: .leading)

            SkeletonBlock(cornerRadius: 4)
                .frame(width: 60, height: 10)
        }
    }
}

struct MediaRowSkeleton: View {
    var cardCount: Int = 5
    var aspectRatio: CGFloat = MediaAspectRatio.poster

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SkeletonBlock(cornerRadius: 6)
                .frame(width: 140, height: 18)
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(0..<cardCount, id: \.self) { _ in
                        MediaCardSkeleton(aspectRatio: aspectRatio)
                            .frame(width: 120)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

struct CarouselSkeleton: View {
    var body: some View {
        SkeletonBlock(cornerRadius: 16)
            .aspectRatio(16 / 9, contentMode: .fit)
            .padding(.horizontal, 16)
    }
}

struct DetailHeaderSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SkeletonBlock(cornerRadius: 0)
                .frame(height: 280)
                .ignoresSafeArea(edges: .top)

            VStack(alignment: .leading, spacing: 10) {
                SkeletonBlock(cornerRadius: 6)
                    .frame(width: 200, height: 24)

                SkeletonBlock(cornerRadius: 4)
                    .frame(width: 120, height: 14)

                SkeletonBlock(cornerRadius: 4)
                    .frame(height: 48)
            }
            .padding(.horizontal, 16)
        }
    }
}

// MARK: - Preview

private let previewSkeletonItems: [BaseItemDto] = (0..<6).map { index in
    BaseItemDto(
        id: "preview-skeleton-\(index)",
        name: "Preview Movie",
        type: .movie
    )
}

#Preview {
    ZStack {
        Color.bg.ignoresSafeArea()
        VStack(alignment: .leading, spacing: 20) {
            SkeletonBlock(cornerRadius: 12)
                .frame(height: 180)
                .padding(.horizontal, 16)

            SectionRow(
                title: "Popular Movies",
                itemIDs: previewSkeletonItems.compactMap(\.id)
            )
            .skeleton()
        }
    }
}
