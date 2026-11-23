//
//  PlayerVideoSurface.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 11/22/26.
//

import SwiftUI
import AVKit

struct PlayerVideoSurface: UIViewRepresentable {
    let player: AVPlayer
    var videoGravity: AVLayerVideoGravity = .resizeAspect
    var onPipControllerCreated: ((AVPictureInPictureController?) -> Void)? = nil

    func makeUIView(context: Context) -> VideoSurfaceUIView {
        let view = VideoSurfaceUIView(player: player, videoGravity: videoGravity)
        if AVPictureInPictureController.isPictureInPictureSupported() {
            let pip = AVPictureInPictureController(playerLayer: view.playerLayer)
            pip?.canStartPictureInPictureAutomaticallyFromInline = true
            context.coordinator.pipController = pip
            DispatchQueue.main.async {
                onPipControllerCreated?(pip)
            }
        }
        return view
    }

    func updateUIView(_ uiView: VideoSurfaceUIView, context: Context) {
        if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
        }
        if uiView.playerLayer.videoGravity != videoGravity {
            uiView.playerLayer.videoGravity = videoGravity
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var pipController: AVPictureInPictureController?
    }
}

final class VideoSurfaceUIView: UIView {
    var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }

    override static var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    init(player: AVPlayer, videoGravity: AVLayerVideoGravity = .resizeAspect) {
        super.init(frame: .zero)
        backgroundColor = .black
        playerLayer.player = player
        playerLayer.videoGravity = videoGravity
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
