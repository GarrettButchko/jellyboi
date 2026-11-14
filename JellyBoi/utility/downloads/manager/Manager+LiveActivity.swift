//
//  Manager+LiveActivity.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 10/8/26.
//

import Foundation
import SDWebImage
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Live Activity Coordination

extension DownloadManager {
    func updateLiveActivity(force: Bool = false) {
        let active = activeDownloads
        guard !active.isEmpty else { return }

        // Bail out before any presentation work when the Live Activity would throttle this update
        // anyway. This runs on every download progress tick, so grouping and artwork lookups here
        // are some of the hottest main-actor work while a download is active.
        let averageProgress = active.reduce(0.0) { $0 + $1.progress } / Double(active.count)
        guard !DownloadActivityCoordinator.shared.isThrottling(
            progress: averageProgress,
            status: DownloadStatus(items: active)
        ) else { return }

        var presentation = currentPresentation
        if presentation.isSingleElement, let posterURL = presentation.posterURL {
            let urlString = posterURL.absoluteString
            if let cached = cachedPosterThumbnails[urlString], cached.count <= 2200 {
                presentation = presentation.with(posterImageData: cached)
            } else {
                let cacheKey = SDWebImageManager.shared.cacheKey(for: posterURL) ?? urlString
                if let image = SDImageCache.shared.imageFromMemoryCache(forKey: cacheKey),
                   let thumbData = image.liveActivityThumbnailData() {
                    // Memory cache only: reading the disk cache here was a synchronous file read
                    // on the main actor. Misses go through the async loader below instead.
                    cachedPosterThumbnails[urlString] = thumbData
                    presentation = presentation.with(posterImageData: thumbData)
                } else {
                    SDWebImageManager.shared.loadImage(
                        with: posterURL,
                        options: [.continueInBackground, .highPriority],
                        progress: nil
                    ) { [weak self] downloadedImage, _, _, _, _, _ in
                        guard let self, let downloadedImage else { return }
                        Task { @MainActor in
                            guard let thumbData = downloadedImage.liveActivityThumbnailData() else { return }
                            self.cachedPosterThumbnails[urlString] = thumbData
                            var updated = self.currentPresentation
                            updated = updated.with(posterImageData: thumbData)
                            DownloadActivityCoordinator.shared.update(presentation: updated, force: true)
                        }
                    }
                }
            }
        }
        DownloadActivityCoordinator.shared.update(presentation: presentation, force: force)
    }
}
