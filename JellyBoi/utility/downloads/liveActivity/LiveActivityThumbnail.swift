//
//  LiveActivityThumbnail.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 10/8/26.
//

import Foundation
#if canImport(UIKit)
import UIKit

// MARK: - UIImage Live Activity Thumbnail

extension UIImage {
    /// Downsamples artwork so it fits within the size budget of a Live Activity payload.
    func liveActivityThumbnailData(maxDimension: CGFloat = 56) -> Data? {
        guard size.width > 0 && size.height > 0 else { return nil }

        let aspect = size.width / size.height
        let targetSize: CGSize
        if aspect > 1.0 {
            // Landscape (e.g. 16:9 episode thumbnail): preserve aspect ratio
            let targetWidth = min(maxDimension, size.width)
            let targetHeight = max(1, round(targetWidth / aspect))
            targetSize = CGSize(width: targetWidth, height: targetHeight)
        } else {
            // Portrait (e.g. 2:3 poster): preserve aspect ratio
            let targetHeight = min(maxDimension, size.height)
            let targetWidth = max(1, round(targetHeight * aspect))
            targetSize = CGSize(width: targetWidth, height: targetHeight)
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let resized = renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: targetSize))
        }

        for quality in [0.6, 0.45, 0.3, 0.15] {
            if let data = resized.jpegData(compressionQuality: quality), data.count <= 2000 {
                return data
            }
        }
        return resized.jpegData(compressionQuality: 0.15)
    }
}
#endif
