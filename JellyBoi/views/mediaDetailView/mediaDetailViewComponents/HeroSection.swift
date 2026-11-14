//
//  MediaDetailHeroSection.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 8/23/26.
//

import SwiftUI
import BaseColors
import SDWebImageSwiftUI
import JellyfinAPI

extension MediaDetailView {

    // MARK: - Hero Section

    private var heroPosterURL: URL? {
        #if DEBUG
        if DebugSettings.shared.hidePoster { return nil }
        #endif
        // Main detail artwork is always requested at full quality.
        if displayItem.type == .episode {
            return displayItem.thumbnailURL(
                client: serverViewModel.client,
                parameters: .thumbnail(maxWidth: 360, quality: 100)
            )
        }
        return displayItem.posterURL(
            client: serverViewModel.client,
            parameters: .detailPoster(quality: 100)
        )
    }

    /// The exact image URL loaded by the source card (cached in memory for instant display during transitions).
    private var cardPosterURL: URL? {
        #if DEBUG
        if DebugSettings.shared.hidePoster { return nil }
        #endif
        if displayItem.type == .episode {
            return displayItem.thumbnailURL(client: serverViewModel.client, parameters: .thumbnail(maxWidth: 360, quality: 65))
        }
        return displayItem.posterURL(client: serverViewModel.client, parameters: .poster(maxWidth: 280, quality: 65))
    }

    /// Low-resolution thumbnail for backdrop blur (saves 94% GPU/memory overhead).
    private var heroBackdropURL: URL? {
        #if DEBUG
        if DebugSettings.shared.hidePoster { return nil }
        #endif
        return displayItem.posterURL(client: serverViewModel.client, parameters: .poster(maxWidth: 120, quality: 50))
    }

    var heroSection: some View {
        HStack(alignment: .bottom, spacing: 8) {
            heroImage
            buttonColumn
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .background(alignment: .top) {
            if AppPreferences.shared.showDetailBlurredBackdrop {
                HeroBackdropView(
                    url: heroBackdropURL,
                    itemID: displayItem.id,
                    blurRadius: 15,
                    isFlipped: true
                )
                .offset(y: -400)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Hero Image

    @ViewBuilder
    var heroImage: some View {
        let currentRatio = detailVM.heroAspectRatio

        if let url = heroPosterURL {
            ZStack {
                heroPlaceholder

                WebImage(
                    url: url,
                    transaction: Transaction(animation: .skeleton)
                ) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFill()
                            .transition(.skeleton)
                    }
                }
                .onSuccess { image, _, _ in
                    detailVM.updateHeroAspectRatio(from: image.size)
                }
            }
            .animatableAspectRatio(currentRatio)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .frame(maxWidth: .infinity)
        } else {
            heroPlaceholder
                .animatableAspectRatio(currentRatio)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var heroPlaceholder: some View {
        if let cardURL = cardPosterURL {
            WebImage(url: cardURL) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .scaledToFill()
                } else {
                    staticHeroPlaceholder
                }
            }
        } else {
            staticHeroPlaceholder
        }
    }

    private var staticHeroPlaceholder: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.sub)
            .overlay {
                Image("Jellyboi")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 75, height: 75)
                    //keep opacity like this please
                    .foregroundStyle(Color.mainOpp.opacity(0.05))
                    .rotationEffect(.degrees(45))
            }
    }
}
