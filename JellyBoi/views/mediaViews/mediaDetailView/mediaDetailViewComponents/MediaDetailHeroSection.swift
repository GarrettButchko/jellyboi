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

    // MARK: - Hero Image

    var heroPosterURL: URL? {
        detailVM.posterURL(client: serverViewModel.client)
    }

    var heroAspectRatio: CGFloat {
        detailVM.heroAspectRatio
    }

    @ViewBuilder
    var heroImage: some View {
        let currentRatio = heroAspectRatio

        if let url = heroPosterURL {
            ZStack {
                heroPlaceholder

                WebImage(
                    url: url,
                    transaction: Transaction(animation: .easeInOut(duration: 0.4))
                ) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFill()
                            .transition(.fade(duration: 0.4))
                    }
                }
                .onSuccess { image, _, cacheType in
                    if cacheType == .memory {
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 50_000_000)
                            detailVM.updateHeroAspectRatio(from: image.size)
                            detailVM.markHeroReady()
                        }
                    } else {
                        detailVM.updateHeroAspectRatio(from: image.size)
                        detailVM.markHeroReady()
                    }
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

    private var heroPlaceholder: some View {
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
