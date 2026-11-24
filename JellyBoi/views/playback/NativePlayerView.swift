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
    var onControlsVisibilityChanged: ((Bool) -> Void)? = nil
    var onFirstFrameReady: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onControlsVisibilityChanged: onControlsVisibilityChanged,
            onFirstFrameReady: onFirstFrameReady
        )
    }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.showsPlaybackControls = true
        controller.updatesNowPlayingInfoCenter = true

        #if os(iOS)
        OrientationHelper.lockOrientation(.allButUpsideDown)
        #endif

        context.coordinator.setupControlsObservation(for: controller)
        context.coordinator.setupDisplayReadinessObservation(for: controller)

        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        if uiViewController.player !== player {
            uiViewController.player = player
        }
        context.coordinator.onControlsVisibilityChanged = onControlsVisibilityChanged
        context.coordinator.onFirstFrameReady = onFirstFrameReady
        context.coordinator.setupControlsObservation(for: uiViewController)
        context.coordinator.setupDisplayReadinessObservation(for: uiViewController)
    }

    static func dismantleUIViewController(_ uiViewController: AVPlayerViewController, coordinator: Coordinator) {
        #if os(iOS)
        OrientationHelper.lockOrientation(.portrait, rotateTo: .portrait)
        #endif

        coordinator.teardown()

        uiViewController.player?.pause()
        uiViewController.player?.rate = 0.0
        if let currentItem = uiViewController.player?.currentItem {
            (currentItem.asset as? AVURLAsset)?.cancelLoading()
        }
        uiViewController.player?.replaceCurrentItem(with: nil)
        uiViewController.player = nil
    }

    final class Coordinator: NSObject {
        var onControlsVisibilityChanged: ((Bool) -> Void)?
        var onFirstFrameReady: (() -> Void)?

        private var observations: [NSKeyValueObservation] = []
        private var displayReadinessObservation: NSKeyValueObservation?
        private var lastReportedVisibility: Bool?
        private var trackingView: ControlsTrackingView?
        private var hasTriggeredFirstFrame: Bool = false

        init(
            onControlsVisibilityChanged: ((Bool) -> Void)?,
            onFirstFrameReady: (() -> Void)? = nil
        ) {
            self.onControlsVisibilityChanged = onControlsVisibilityChanged
            self.onFirstFrameReady = onFirstFrameReady
        }

        func setupDisplayReadinessObservation(for controller: AVPlayerViewController) {
            guard displayReadinessObservation == nil else { return }

            displayReadinessObservation = controller.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] controller, change in
                guard let self else { return }
                let isReady = change.newValue ?? controller.isReadyForDisplay
                if isReady && !self.hasTriggeredFirstFrame {
                    self.hasTriggeredFirstFrame = true
                    Task { @MainActor [weak self] in
                        self?.onFirstFrameReady?()
                    }
                }
            }
        }

        func setupControlsObservation(for controller: AVPlayerViewController) {
            guard observations.isEmpty else { return }

            if let overlay = controller.contentOverlayView {
                if trackingView == nil {
                    let tracker = ControlsTrackingView()
                    tracker.frame = .zero
                    tracker.isHidden = true
                    tracker.onHierarchyReady = { [weak self, weak controller] in
                        guard let self, let controller else { return }
                        self.attachObservers(to: controller)
                    }
                    overlay.addSubview(tracker)
                    self.trackingView = tracker
                }
            }

            attachObservers(to: controller)
        }

        private func attachObservers(to controller: AVPlayerViewController) {
            guard observations.isEmpty else { return }

            let viewsToObserve: [UIView] = {
                if let overlay = controller.contentOverlayView,
                   let container = overlay.superview {
                    if let overlayIndex = container.subviews.firstIndex(of: overlay) {
                        let candidateViews = container.subviews.suffix(from: overlayIndex + 1)
                        if !candidateViews.isEmpty {
                            return Array(candidateViews)
                        }
                    }
                }
                return controller.view.subviews.filter { subview in
                    subview !== controller.contentOverlayView
                }
            }()

            for view in viewsToObserve {
                let alphaObs = view.observe(\.alpha, options: [.initial, .new]) { [weak self] observedView, change in
                    guard let self else { return }
                    let currentAlpha = change.newValue ?? observedView.alpha
                    let isVisible = currentAlpha > 0.05 && !observedView.isHidden
                    self.updateControlsVisibility(isVisible)
                }
                let hiddenObs = view.observe(\.isHidden, options: [.initial, .new]) { [weak self] observedView, change in
                    guard let self else { return }
                    let isHidden = change.newValue ?? observedView.isHidden
                    let isVisible = !isHidden && observedView.alpha > 0.05
                    self.updateControlsVisibility(isVisible)
                }
                observations.append(alphaObs)
                observations.append(hiddenObs)
            }
        }

        private func updateControlsVisibility(_ isVisible: Bool) {
            Task { @MainActor [weak self] in
                guard let self, self.lastReportedVisibility != isVisible else { return }
                self.lastReportedVisibility = isVisible
                self.onControlsVisibilityChanged?(isVisible)
            }
        }

        func teardown() {
            observations.forEach { $0.invalidate() }
            observations.removeAll()
            displayReadinessObservation?.invalidate()
            displayReadinessObservation = nil
            trackingView?.removeFromSuperview()
            trackingView = nil
        }
    }
}

private final class ControlsTrackingView: UIView {
    var onHierarchyReady: (() -> Void)?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            onHierarchyReady?()
        }
    }
}
