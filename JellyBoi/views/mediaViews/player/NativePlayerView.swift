//
//  NativePlayerView.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 10/5/26.
//

import SwiftUI
import AVKit

struct NativePlayerView: UIViewControllerRepresentable {
    let player: AVPlayer
    var onDismiss: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(onDismiss: onDismiss)
    }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.showsPlaybackControls = true
        controller.updatesNowPlayingInfoCenter = true
        controller.delegate = context.coordinator

        #if os(iOS)
        OrientationHelper.lockOrientation(.allButUpsideDown)
        #endif

        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        if uiViewController.player !== player {
            uiViewController.player = player
        }
        context.coordinator.onDismiss = onDismiss
    }

    static func dismantleUIViewController(_ uiViewController: AVPlayerViewController, coordinator: Coordinator) {
        #if os(iOS)
        OrientationHelper.lockOrientation(.portrait, rotateTo: .portrait)
        #endif

        uiViewController.player?.pause()
        uiViewController.player?.rate = 0.0
        if let currentItem = uiViewController.player?.currentItem {
            (currentItem.asset as? AVURLAsset)?.cancelLoading()
        }
        uiViewController.player?.replaceCurrentItem(with: nil)
        uiViewController.player = nil
        coordinator.onDismiss?()
    }

    final class Coordinator: NSObject, AVPlayerViewControllerDelegate {
        var onDismiss: (() -> Void)?

        init(onDismiss: (() -> Void)?) {
            self.onDismiss = onDismiss
        }

        func playerViewController(
            _ playerViewController: AVPlayerViewController,
            willEndFullScreenPresentationWithAnimationCoordinator coordinator: any UIViewControllerTransitionCoordinator
        ) {
            coordinator.animate(alongsideTransition: nil) { [weak self] context in
                if context.isCancelled {
                    return
                }
                if playerViewController.player?.isExternalPlaybackActive == true {
                    return
                }
                self?.onDismiss?()
            }
        }
    }
}
