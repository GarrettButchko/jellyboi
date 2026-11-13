//
//  ArtworkLoader.swift
//  JellyBoi
//

import Foundation
import UIKit
import JellyfinAPI
import LoggingKit
import SDWebImage

/// Loads poster artwork for Now Playing metadata.
///
/// Reads go through SDWebImage's shared cache first, so the image a card already downloaded is
/// reused instead of fetched again for the lock screen.
enum ArtworkLoader {

    /// Returns artwork synchronously from SDWebImage's memory or disk cache.
    static func cached(for item: BaseItemDto, client: JellyfinClient?) -> (data: Data, image: UIImage)? {
        let urls = item.artworkURLs(client: client)
        guard !urls.isEmpty else { return nil }

        for url in urls {
            let cacheKey = SDWebImageManager.shared.cacheKey(for: url) ?? url.absoluteString
            if let image = SDImageCache.shared.imageFromMemoryCache(forKey: cacheKey)
                ?? SDImageCache.shared.imageFromDiskCache(forKey: cacheKey),
               let data = image.jpegData(compressionQuality: 0.85) ?? image.pngData() {
                AppLogger.debug("Loaded poster artwork from SDImageCache for \(item.playbackTitle)")
                return (data, image)
            }
        }

        return nil
    }

    /// Returns cached artwork when available, otherwise downloads it and stores it in the cache.
    static func load(
        for item: BaseItemDto,
        client: JellyfinClient?,
        timeoutSeconds: Double = 5.0
    ) async -> (data: Data, image: UIImage)? {
        if let cached = cached(for: item, client: client) {
            return cached
        }

        for url in item.artworkURLs(client: client) {
            if let result = await fetchImage(for: url, timeoutSeconds: timeoutSeconds) {
                AppLogger.debug("Downloaded poster artwork for \(item.playbackTitle)")
                return result
            }
        }

        return nil
    }

    /// Downloads a single image and writes it into the shared cache.
    private static func fetchImage(for url: URL, timeoutSeconds: Double) async -> (data: Data, image: UIImage)? {
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = timeoutSeconds
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let image = UIImage(data: data) else {
                return nil
            }
            let cacheKey = SDWebImageManager.shared.cacheKey(for: url) ?? url.absoluteString
            await SDImageCache.shared.store(image, imageData: data, forKey: cacheKey, toDisk: true)
            return (data, image)
        } catch {
            AppLogger.debug("Network artwork fetch failed for \(url.lastPathComponent): \(error.localizedDescription)")
            return nil
        }
    }
}
