//
//  PlayerViewModel+Diagnostics.swift
//  JellyBoi
//

import Foundation
import AVKit
import JellyfinAPI

extension PlayerViewModel {

    /// One-line summary of how the current item is being delivered, shown in the debug overlay.
    #if DEBUG
    public var playbackDiagnosticSummary: String {
        var items: [String] = []
        items.append("Method: \(streamContext.playMethod.rawValue)")
        if let local = request.localFileURL {
            items.append("Local: \(local.lastPathComponent)")
            let size = (try? FileManager.default.attributesOfItem(atPath: local.path)[.size] as? Int64) ?? 0
            if size > 0 {
                items.append("Size: \(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))")
            }
        } else {
            items.append("Source: Server Stream")
        }
        if let current = player?.currentItem {
            let tracks = current.tracks
            let videoTracks = tracks.filter { $0.assetTrack?.mediaType == .video }
            let audioTracks = tracks.filter { $0.assetTrack?.mediaType == .audio }
            let presentationSize = current.presentationSize
            let videoSize = streamContext.videoNaturalSize ?? (presentationSize != .zero ? presentationSize : nil)
            if videoTracks.isEmpty {
                items.append("Video: None (Audio Only)")
            } else if let v = videoTracks.first {
                if let size = videoSize {
                    let w = Int(size.width)
                    let h = Int(size.height)
                    items.append("Video: \(w)x\(h) [\(v.isEnabled ? "Active" : "Disabled")]")
                } else {
                    if let at = v.assetTrack {
                        Task { @MainActor [weak self] in
                            if let size = try? await at.load(.naturalSize), size.width > 0, size.height > 0 {
                                self?.streamContext.videoNaturalSize = size
                            }
                        }
                    }
                    items.append("Video: Track Present [\(v.isEnabled ? "Active" : "Disabled")]")
                }
            } else {
                items.append("Video: Track Present")
            }
            items.append("Audio: \(audioTracks.count) track(s)")
        }
        return items.joined(separator: " • ")
    }
    #endif
}
