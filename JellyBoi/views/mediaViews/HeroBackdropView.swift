//
//  HeroBackdropView.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 9/9/26.
//

import SwiftUI
import SDWebImage

/// A full-bleed, blurred backdrop image with top-to-bottom gradient fading.
/// Shared between the carousel background in `HomeView` and the hero background in `MediaDetailView`.
struct HeroBackdropView: View {
    let url: URL?
    var itemID: String? = nil
    var height: CGFloat = 1150
    var blurRadius: CGFloat = 40
    var isFlipped: Bool = false
    var gradientColors: [Color] = [.black, .black.opacity(0.5), .clear]
    var ignoresSafeAreaEdges: Edge.Set = .all

    @State private var imageA: UIImage? = nil
    @State private var imageB: UIImage? = nil
    @State private var bOpacity: Double = 0.0
    @State private var isBTarget: Bool = false
    @State private var contentOpacity: Double = 0.0
    @State private var currentLoadedURL: URL? = nil

    private struct BackdropKey: Equatable, Hashable {
        let url: URL?
        let itemID: String?
        let blurRadius: CGFloat
    }

    var body: some View {
        ZStack {
            if let imageA {
                Image(uiImage: imageA)
                    .resizable()
                    .scaledToFill()
                    .scaleEffect(x: isFlipped ? -1 : 1, y: 1)
            }
            if let imageB {
                Image(uiImage: imageB)
                    .resizable()
                    .scaledToFill()
                    .scaleEffect(x: isFlipped ? -1 : 1, y: 1)
                    .opacity(bOpacity)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .mask(
            LinearGradient(
                colors: gradientColors,
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .opacity(contentOpacity)
        .ignoresSafeArea(edges: ignoresSafeAreaEdges)
        .task(id: BackdropKey(url: url, itemID: itemID, blurRadius: blurRadius)) {
            await handleImageChange()
        }
    }

    @MainActor
    private func handleImageChange() async {
        guard let url else {
            withAnimation(.easeInOut(duration: 0.35)) {
                contentOpacity = 0.0
            }
            currentLoadedURL = nil
            return
        }

        if url == currentLoadedURL && (imageA != nil || imageB != nil) {
            return
        }

        guard let newImage = await fetchImage(for: url) else { return }
        guard !Task.isCancelled else { return }

        currentLoadedURL = url

        // First image being loaded
        if imageA == nil && imageB == nil {
            imageA = newImage
            bOpacity = 0.0
            isBTarget = false
            withAnimation(.easeInOut(duration: 0.4)) {
                contentOpacity = 1.0
            }
            return
        }

        if contentOpacity < 1.0 {
            withAnimation(.easeInOut(duration: 0.35)) {
                contentOpacity = 1.0
            }
        }

        // Crossfade to the next image without exposing the background:
        // - One layer stays at 100% opacity underneath.
        // - The other layer fades in or out on top.
        // - Total composite opacity is always 100%, seamlessly merging the two images.
        if isBTarget {
            // Layer B is currently on top. Load new image into Layer A underneath,
            // then fade Layer B out from 1.0 to 0.0 to reveal Layer A.
            imageA = newImage
            isBTarget = false
            withAnimation(.easeInOut(duration: 0.45)) {
                bOpacity = 0.0
            }
        } else {
            // Layer A is currently visible. Load new image into Layer B on top,
            // then fade Layer B in from 0.0 to 1.0 over Layer A.
            imageB = newImage
            isBTarget = true
            withAnimation(.easeInOut(duration: 0.45)) {
                bOpacity = 1.0
            }
        }
    }

    private func fetchImage(for url: URL) async -> UIImage? {
        let transformer = blurRadius > 0 ? SDImageBlurTransformer(radius: blurRadius) : nil
        let context: [SDWebImageContextOption: Any]? = transformer.map { [.imageTransformer: $0] }
        let cacheKey = SDWebImageManager.shared.cacheKey(for: url, context: context)
        if let cached = SDImageCache.shared.imageFromMemoryCache(forKey: cacheKey) {
            return cached
        }

        final class StateBox: @unchecked Sendable {
            var resumed = false
            var operation: SDWebImageOperation?
            let lock = NSLock()

            func resume(with continuation: CheckedContinuation<UIImage?, Never>, image: UIImage?) {
                lock.lock()
                defer { lock.unlock() }
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: image)
            }

            @MainActor
            func cancel() {
                lock.lock()
                let op = operation
                lock.unlock()
                op?.cancel()
            }
        }

        let box = StateBox()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let op = SDWebImageManager.shared.loadImage(
                    with: url,
                    options: [.avoidAutoSetImage, .retryFailed],
                    context: context,
                    progress: nil
                ) { image, _, _, _, finished, _ in
                    if finished {
                        box.resume(with: continuation, image: image)
                    }
                }
                box.lock.lock()
                box.operation = op
                if op == nil {
                    box.lock.unlock()
                    box.resume(with: continuation, image: nil)
                } else {
                    box.lock.unlock()
                }
            }
        } onCancel: {
            Task { @MainActor in
                box.cancel()
            }
        }
    }
}
