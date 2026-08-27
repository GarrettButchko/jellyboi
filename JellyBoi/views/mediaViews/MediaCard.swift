//
//  MediaCard.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 8/25/26.
//

import SwiftUI
import BaseColors
import SDWebImageSwiftUI
import JellyfinAPI

struct MediaCard: View {
    let item: BaseItemDto
    let posterURL: URL?
    let namespace: Namespace.ID
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            posterImage
                .aspectRatio(2/3, contentMode: .fit)
                .overlay(alignment: .bottomTrailing) {
                    if let progress = watchProgress, !isWatched {
                        GlassProgressBar(progress: progress, barWidth: 40)
                            .padding(8)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if isWatched {
                        watchedBadge
                            .padding(8)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .matchedTransitionSource(id: item, in: namespace)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var watchProgress: Double? {
        if item.userData?.isPlayed == true { return 1 }
        guard let percent = item.userData?.playedPercentage else { return nil }
        return min(max(percent / 100, 0), 1)
    }

    private var isWatched: Bool {
        (watchProgress ?? 0) >= 0.85
    }

    private var watchedBadge: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(Color.mainOpp)
            .padding(6)
            .glassEffect(.clear.tint(Color.main.opacity(0.8)), in: Circle())
    }


    @ViewBuilder
    private var posterImage: some View {
        if let url = posterURL {
            WebImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                placeholder
            }
            .frame(maxWidth: .infinity)
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        Color.sub
            .overlay {
                AnimatedImage(name: "jellyFishAniBlack.gif")
                    .playbackRate(2.0)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 50, height: 50)
                    .opacity(0.05)
                    .rotationEffect(Angle(degrees: 45))
            }
    }
}
