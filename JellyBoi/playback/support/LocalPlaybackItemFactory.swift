//
//  LocalPlaybackItemFactory.swift
//  JellyBoi
//

import AVFoundation
import CoreGraphics
import LoggingKit

/// Builds `AVPlayerItem`s for downloaded files that AVPlayer can open natively.
///
/// Local playback is deliberately simple: no negotiation and no server, just a file check plus an
/// aspect-ratio correction when the container's display ratio disagrees with Jellyfin metadata.
enum LocalPlaybackItemFactory {

    struct Result {
        let playerItem: AVPlayerItem
        let naturalSize: CGSize?
    }

    /// Returns `nil` when the file is not playable by AVPlayer, which signals the caller to fall
    /// back to streaming from the server.
    static func make(url: URL, targetAspectRatio: Double?) async -> Result? {
        let asset = AVURLAsset(url: url)
        let isPlayable = (try? await asset.load(.isPlayable)) ?? false
        guard isPlayable else {
            AppLogger.warning("Local file at \(url.path) cannot be opened by AVPlayer. Falling back to server stream.")
            return nil
        }

        AppLogger.info("Preparing local file playback from: \(url.path)")
        let playerItem = AVPlayerItem(asset: asset)
        var naturalSize: CGSize?

        if let tracks = try? await asset.loadTracks(withMediaType: .video),
           let videoTrack = tracks.first,
           let size = try? await videoTrack.load(.naturalSize),
           size.width > 0, size.height > 0 {
            naturalSize = size

            if let composition = await makeAspectRatioCompositionIfNeeded(
                for: videoTrack,
                naturalSize: size,
                targetAspectRatio: targetAspectRatio
            ) {
                playerItem.videoComposition = composition
            }
        }

        return Result(playerItem: playerItem, naturalSize: naturalSize)
    }

    // MARK: - Aspect Ratio Correction

    /// Wraps the track in a video composition when its display ratio differs from the target ratio
    /// by more than 2%, stretching horizontally to match without changing the frame height.
    private static func makeAspectRatioCompositionIfNeeded(
        for videoTrack: AVAssetTrack,
        naturalSize: CGSize,
        targetAspectRatio: Double?
    ) async -> AVVideoComposition? {
        let trackDAR = naturalSize.width / naturalSize.height
        guard let targetDAR = targetAspectRatio, abs(trackDAR - targetDAR) / targetDAR > 0.02 else {
            return nil
        }

        let preferredTransform = (try? await videoTrack.load(.preferredTransform)) ?? .identity
        let renderWidth = naturalSize.height * targetDAR
        let renderHeight = naturalSize.height
        let scaleX = renderWidth / naturalSize.width

        var layerConfig = AVVideoCompositionLayerInstruction.Configuration(assetTrack: videoTrack)
        let adjustedTransform = preferredTransform.scaledBy(x: scaleX, y: 1.0)
        layerConfig.setTransform(adjustedTransform, at: .zero)
        let layerInstruction = AVVideoCompositionLayerInstruction(configuration: layerConfig)

        var instructionConfig = AVVideoCompositionInstruction.Configuration()
        instructionConfig.timeRange = CMTimeRange(start: .zero, duration: .positiveInfinity)
        instructionConfig.layerInstructions = [layerInstruction]
        let instruction = AVVideoCompositionInstruction(configuration: instructionConfig)

        var compositionConfig = AVVideoComposition.Configuration()
        compositionConfig.instructions = [instruction]
        compositionConfig.renderSize = CGSize(width: renderWidth, height: renderHeight)
        let nominalFrameRate = (try? await videoTrack.load(.nominalFrameRate)) ?? 0
        let fps = nominalFrameRate > 0 ? Int32(round(nominalFrameRate)) : 30
        compositionConfig.frameDuration = CMTime(value: 1, timescale: fps)

        return AVVideoComposition(configuration: compositionConfig)
    }
}
