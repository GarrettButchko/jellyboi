//
//  MediaDetailHeroSection.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 8/23/26.
//

import SwiftUI
import UIKit
import BaseColors
import SDWebImageSwiftUI
import JellyfinAPI

private var deviceCornerRadius: CGFloat {
    let screen = UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .first?
        .screen
    return (screen?.value(forKey: "_displayCornerRadius") as? CGFloat) ?? 49
}



extension MediaDetailView {

    // MARK: - Backdrop

    @ViewBuilder
    var heroBackdrop: some View {
        if let url = detailVM.backdropURL {
            WebImage(url: url) { image in
                image.resizable().scaledToFill().scaleEffect(x: -1, y: 1)
            } placeholder: { Color.clear }
                .frame(maxWidth: .infinity)
                .frame(height: 1150)
                .blur(radius: 50)
                .mask(
                    LinearGradient(
                        colors: [.black, .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .ignoresSafeArea(edges: .top)
                .id(item.id)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.3), value: item.id)
        } else {
            Color.sub
        }
    }

    // MARK: - Hero Image

    @ViewBuilder
    var heroImage: some View {
        if let url = detailVM.posterURL {
            WebImage(url: url) { image in
                image.resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(color: .black.opacity(0.5), radius: 24, x: 0, y: 8)
            } placeholder: {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.sub)
                    .aspectRatio(2/3, contentMode: .fit)
            }
            .onSuccess { _, _, _ in
                detailVM.markHeroReady()
            }
            .opacity(detailVM.heroReady ? 1 : 0)
            .animation(.easeIn(duration: 0.35), value: detailVM.heroReady)
            .frame(maxWidth: .infinity)
        } else {
            Color.clear
                .aspectRatio(3/5, contentMode: .fit)
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Hero Title

    @ViewBuilder
    var heroTitleView: some View {
        if let url = detailVM.logoURL {
            WebImage(url: url) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                Text(heroTitle)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: 280, maxHeight: 80)
        } else {
            Text(heroTitle)
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    var heroTitle: String {
        if item.type == .episode {
            return item.episodeTitle ?? item.name ?? ""
        }
        return item.name ?? ""
    }

    var heroEpisodeLabel: String? {
        guard item.type == .episode else { return nil }
        if let series = item.seriesName,
           let season = item.parentIndexNumber,
           let ep = item.indexNumber {
            return "\(series) · S\(season) E\(ep)"
        }
        return item.seriesName
    }
}

// MARK: - BleedingHeroShape

/// A custom hero header shape that bleeds past the left, top, and right edges to prevent
/// anti-aliasing light lines, while maintaining smooth rounded corners at the bottom.
extension MediaDetailView {
    struct BleedingHeroShape: Shape {
        var bottomRadius: CGFloat
        var bleed: CGFloat = 1.7

        var animatableData: CGFloat {
            get { bottomRadius }
            set { bottomRadius = newValue }
        }

        func path(in rect: CGRect) -> Path {
            let bleedRect = CGRect(
                x: rect.minX - bleed,
                y: rect.minY - bleed,
                width: rect.width + bleed * 2,
                height: rect.height + bleed
            )
            let r = min(bottomRadius, rect.width / 2, rect.height / 2)
            return UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: r,
                bottomTrailingRadius: r,
                topTrailingRadius: 0,
                style: .continuous
            ).path(in: bleedRect)
        }
    }
}
