//
//  CustomPlayerView.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 11/22/26.
//

import SwiftUI
import AVKit
import SDWebImageSwiftUI
import JellyfinAPI
import LoggingKit

struct CustomPlayerView: View {
    let player: AVPlayer
    var itemID: String? = nil
    var nextItem: BaseItemDto? = nil
    var onPlayNext: (() -> Void)? = nil
    var onDismiss: (() -> Void)? = nil
    var onControlsVisibilityChanged: ((Bool) -> Void)? = nil

    // MARK: - Playback & Loading State

    @State private var isLoading: Bool = true
    @State private var isPlaying: Bool = false
    @State private var currentTime: Double = 0.0
    @State private var duration: Double = 0.0
    @State private var isScrubbing: Bool = false
    @State private var scrubProgress: Double = 0.0
    @State private var volume: Float = 1.0
    @State private var areControlsVisible: Bool = true
    @State private var autoHideTask: Task<Void, Never>? = nil
    @State private var pipController: AVPictureInPictureController? = nil
    @State private var isPipActive: Bool = false
    @State private var isSubtitlesOn: Bool = false
    @State private var legibleGroup: AVMediaSelectionGroup? = nil
    @State private var availableLegibleOptions: [AVMediaSelectionOption] = []
    @State private var timeObserverToken: Any? = nil

    @Namespace private var glassNamespace

    // KVO Observations
    @State private var timeControlStatusObservation: NSKeyValueObservation? = nil
    @State private var currentItemObservation: NSKeyValueObservation? = nil
    @State private var statusObservation: NSKeyValueObservation? = nil
    @State private var bufferEmptyObservation: NSKeyValueObservation? = nil
    @State private var likelyToKeepUpObservation: NSKeyValueObservation? = nil
    @State private var pipActiveObservation: NSKeyValueObservation? = nil

    var body: some View {
        ZStack {
            // Background Video Surface
            PlayerVideoSurface(
                player: player,
                videoGravity: .resizeAspect,
                onPipControllerCreated: { pip in
                    self.pipController = pip
                    self.pipActiveObservation?.invalidate()
                    self.pipActiveObservation = pip?.observe(\.isPictureInPictureActive, options: [.initial, .new]) { controller, _ in
                        Task { @MainActor in
                            withAnimation(.easeInOut(duration: 0.25)) {
                                self.isPipActive = controller.isPictureInPictureActive
                            }
                        }
                    }
                }
            )
            .ignoresSafeArea()
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.25)) {
                    areControlsVisible.toggle()
                }
                if areControlsVisible {
                    resetAutoHideTimer()
                }
            }

            // Controls Overlay
            ZStack {
                if areControlsVisible {
                    centerControls
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                        .zIndex(1)
                }

                VStack {
                    if areControlsVisible {
                        topBar
                            .padding(.horizontal, 24)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    Spacer()

                    if areControlsVisible {
                        bottomSection
                            .padding(.horizontal, 24)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
            .safeAreaPadding()
            .animation(.easeInOut(duration: 0.25), value: areControlsVisible)
        }
        .environment(\.colorScheme, .dark)
        .preferredColorScheme(.dark)
        .onAppear {
            setupPlayerObservations()
            startPlayback()
            resetAutoHideTimer()
        }
        .onDisappear {
            teardownPlayerObservations()
        }
        .onChange(of: areControlsVisible) { _, isVisible in
            onControlsVisibilityChanged?(isVisible)
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(alignment: .center) {
            // Dismiss button (Always White)
            Button {
                onDismiss?()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 44, height: 44)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .playerGlass(in: Circle())

            // PiP & AirPlay (Always White)
            GlassEffectContainer(spacing: 20.0) {
                HStack(spacing: 20) {
                    if let pip = pipController {
                        Button {
                            if pip.isPictureInPictureActive {
                                pip.stopPictureInPicture()
                            } else {
                                pip.startPictureInPicture()
                            }
                        } label: {
                            Image(systemName: isPipActive ? "pip.exit" : "pip.enter")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(Color.white)
                                .frame(width: 44, height: 44)
                                .contentTransition(.symbolEffect(.replace))
                        }
                        .buttonStyle(.plain)
                        .playerGlass(in: Circle())
                        .glassEffectID("pip", in: glassNamespace)
                        .animation(.smooth, value: isPipActive)
                    }

                    AirPlayPickerView()
                        .frame(width: 44, height: 44)
                        .playerGlass(in: Circle())
                        .glassEffectID("airPlay", in: glassNamespace)
                }
            }

            Spacer()

            // Volume Capsule (Always White)
            HStack(spacing: 10) {
                CustomVolumeSlider(
                    volume: $volume,
                    onEditingChanged: { isEditing in
                        if isEditing {
                            cancelAutoHideTimer()
                        } else {
                            resetAutoHideTimer()
                        }
                    },
                    onVolumeChanged: { newVol in
                        player.volume = newVol
                    }
                )
                .frame(width: 110, height: 20)

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if volume > 0 {
                            volume = 0
                        } else {
                            volume = 1.0
                        }
                    }
                    player.volume = volume
                    resetAutoHideTimer()
                } label: {
                    Image(systemName: volumeIcon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .frame(width: 20, height: 20)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
                .animation(.smooth, value: volumeIcon)
            }
            .padding(.horizontal, 16)
            .frame(height: 44)
            .playerGlass(in: Capsule())
        }
    }

    private var volumeIcon: String {
        if volume == 0 {
            return "speaker.slash.fill"
        } else if volume < 0.33 {
            return "speaker.wave.1.fill"
        } else if volume < 0.66 {
            return "speaker.wave.2.fill"
        } else {
            return "speaker.wave.3.fill"
        }
    }

    // MARK: - Center Transport Controls

    private var centerControls: some View {
        GlassEffectContainer(spacing: 28.0) {
            HStack(spacing: 28.0) {
                // Backward 10 seconds (Always White)
                Button {
                    seekRelative(by: -10)
                    resetAutoHideTimer()
                } label: {
                    Image(systemName: "gobackward.10")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .frame(width: 62, height: 62)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
                .playerGlass(in: Circle())
                .glassEffectID("backward", in: glassNamespace)

                // Center Play / Pause or Animated JellyBoi loading indicator
                Button {
                    if !isLoading {
                        togglePlayPause()
                        resetAutoHideTimer()
                    }
                } label: {
                    ZStack {
                        if isLoading {
                            // Animated JellyBoi GIF when loading / buffering (Always White)
                            AnimatedImage(name: "jellyFishAniWhite.gif", bundle: .main)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 44, height: 44)
                                .rotationEffect(Angle(degrees: 45))
                        } else {
                            // Play / Pause Icon (Always White)
                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 34, weight: .bold))
                                .foregroundStyle(Color.white)
                                .contentTransition(.symbolEffect(.replace))
                        }
                    }
                    .frame(width: 84, height: 84)
                    .animation(.smooth, value: isPlaying)
                    .animation(.easeInOut(duration: 0.2), value: isLoading)
                }
                .buttonStyle(.plain)
                .playerGlass(in: Circle())
                .glassEffectID("playPause", in: glassNamespace)

                // Forward 10 seconds (Always White)
                Button {
                    seekRelative(by: 10)
                    resetAutoHideTimer()
                } label: {
                    Image(systemName: "goforward.10")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .frame(width: 62, height: 62)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
                .playerGlass(in: Circle())
                .glassEffectID("forward", in: glassNamespace)

                // Next Play / Next Episode button (Always White)
                if onPlayNext != nil || nextItem != nil {
                    Button {
                        onPlayNext?()
                        resetAutoHideTimer()
                    } label: {
                        Image(systemName: "forward.end.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(Color.white)
                            .frame(width: 62, height: 62)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(.plain)
                    .playerGlass(in: Circle())
                    .glassEffectID("next", in: glassNamespace)
                }
            }
        }
    }

    // MARK: - Bottom Section

    private var bottomSection: some View {
        VStack(alignment: .trailing, spacing: 14) {
            // Audio / Subtitles Button (Always White)
            Menu {
                if let item = player.currentItem,
                   let group = legibleGroup,
                   !availableLegibleOptions.isEmpty {
                    Section("Subtitles") {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                item.select(nil, in: group)
                                isSubtitlesOn = false
                            }
                        } label: {
                            if !isSubtitlesOn {
                                Label("Off", systemImage: "checkmark")
                            } else {
                                Text("Off")
                            }
                        }

                        ForEach(availableLegibleOptions, id: \.displayName) { option in
                            let isSelected = (item.currentMediaSelection.selectedMediaOption(in: group) == option)
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    item.select(option, in: group)
                                    isSubtitlesOn = true
                                }
                            } label: {
                                if isSelected {
                                    Label(option.displayName, systemImage: "checkmark")
                                } else {
                                    Text(option.displayName)
                                }
                            }
                        }
                    }
                } else {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isSubtitlesOn.toggle()
                        }
                    } label: {
                        Label(
                            isSubtitlesOn ? "Subtitles On" : "Subtitles Off",
                            systemImage: isSubtitlesOn ? "captions.bubble.fill" : "captions.bubble"
                        )
                    }
                }
            } label: {
                Image(systemName: isSubtitlesOn ? "captions.bubble.fill" : "captions.bubble")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(width: 44, height: 44)
                    .contentTransition(.symbolEffect(.replace))
            }
            .animation(.smooth, value: isSubtitlesOn)
            .playerGlass(in: Circle())

            // Scrubber Capsule (Always White)
            HStack(spacing: 14) {
                let displayCurrent = isScrubbing ? (scrubProgress * duration) : currentTime
                let displayRemaining = max(0, duration - displayCurrent)

                Text(formatTime(displayCurrent))
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.9))

                CustomScrubber(
                    progress: isScrubbing ? scrubProgress : (duration > 0 ? (currentTime / duration) : 0),
                    onScrubStart: {
                        isScrubbing = true
                        scrubProgress = duration > 0 ? (currentTime / duration) : 0
                        cancelAutoHideTimer()
                    },
                    onScrubChange: { fraction in
                        scrubProgress = fraction
                    },
                    onScrubEnd: { fraction in
                        let targetSeconds = fraction * duration
                        seek(to: targetSeconds)
                        isScrubbing = false
                        resetAutoHideTimer()
                    }
                )
                .frame(height: 20)

                Text("-" + formatTime(displayRemaining))
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.9))
            }
            .padding(.horizontal, 20)
            .frame(height: 48)
            .playerGlass(in: Capsule())
        }
    }

    // MARK: - Playback Logic

    private func startPlayback() {
        player.play()
        volume = player.volume
        updateLoadingState()
    }

    private func togglePlayPause() {
        withAnimation(.easeInOut(duration: 0.2)) {
            if isPlaying {
                player.pause()
                isPlaying = false
            } else {
                player.play()
                isPlaying = true
            }
        }
    }

    private func seekRelative(by seconds: Double) {
        let target = max(0, min(duration, currentTime + seconds))
        seek(to: target)
    }

    private func seek(to targetSeconds: Double) {
        let cmTime = CMTime(seconds: targetSeconds, preferredTimescale: 600)
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = targetSeconds
    }

    // MARK: - Player & Loading Observations

    private func setupPlayerObservations() {
        updateLoadingState()

        timeControlStatusObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { _, _ in
            Task { @MainActor in
                updateLoadingState()
            }
        }

        currentItemObservation = player.observe(\.currentItem, options: [.initial, .new]) { _, _ in
            Task { @MainActor in
                setupItemObservations(for: player.currentItem)
                updateLoadingState()
            }
        }

        setupItemObservations(for: player.currentItem)

        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak player] time in
            guard let player else { return }
            if !isScrubbing {
                currentTime = time.seconds
                if let itemDuration = player.currentItem?.duration.seconds, !itemDuration.isNaN, itemDuration > 0 {
                    duration = itemDuration
                }
            }
            updateLoadingState()
        }
    }

    private func setupItemObservations(for item: AVPlayerItem?) {
        guard let item else { return }

        statusObservation = item.observe(\.status, options: [.initial, .new]) { _, _ in
            Task { @MainActor in
                updateLoadingState()
                await updateSubtitlesState()
            }
        }

        bufferEmptyObservation = item.observe(\.isPlaybackBufferEmpty, options: [.new]) { _, _ in
            Task { @MainActor in
                updateLoadingState()
            }
        }

        likelyToKeepUpObservation = item.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) { _, _ in
            Task { @MainActor in
                updateLoadingState()
            }
        }

        Task { @MainActor in
            await updateSubtitlesState()
        }
    }

    private func updateSubtitlesState() async {
        guard let item = player.currentItem else {
            legibleGroup = nil
            availableLegibleOptions = []
            withAnimation(.easeInOut(duration: 0.2)) {
                isSubtitlesOn = false
            }
            return
        }

        do {
            let group = try await item.asset.loadMediaSelectionGroup(for: .legible)
            legibleGroup = group
            availableLegibleOptions = group?.options ?? []
            if let group {
                let selected = item.currentMediaSelection.selectedMediaOption(in: group)
                withAnimation(.easeInOut(duration: 0.2)) {
                    isSubtitlesOn = (selected != nil)
                }
            } else {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isSubtitlesOn = false
                }
            }
        } catch {
            legibleGroup = nil
            availableLegibleOptions = []
            withAnimation(.easeInOut(duration: 0.2)) {
                isSubtitlesOn = false
            }
        }
    }

    private func updateLoadingState() {
        guard let item = player.currentItem else {
            withAnimation(.easeInOut(duration: 0.2)) {
                isLoading = true
                isPlaying = false
            }
            return
        }

        withAnimation(.easeInOut(duration: 0.2)) {
            if item.status != .readyToPlay {
                isLoading = true
                isPlaying = false
            } else if player.timeControlStatus == .waitingToPlayAtSpecifiedRate {
                isLoading = true
                isPlaying = false
            } else if item.isPlaybackBufferEmpty && !item.isPlaybackLikelyToKeepUp {
                isLoading = true
                isPlaying = false
            } else {
                isLoading = false
                isPlaying = (player.timeControlStatus == .playing)
            }
        }
    }

    private func teardownPlayerObservations() {
        timeControlStatusObservation?.invalidate()
        timeControlStatusObservation = nil
        currentItemObservation?.invalidate()
        currentItemObservation = nil
        statusObservation?.invalidate()
        statusObservation = nil
        bufferEmptyObservation?.invalidate()
        bufferEmptyObservation = nil
        likelyToKeepUpObservation?.invalidate()
        likelyToKeepUpObservation = nil
        pipActiveObservation?.invalidate()
        pipActiveObservation = nil

        if let token = timeObserverToken {
            player.removeTimeObserver(token)
            timeObserverToken = nil
        }
        cancelAutoHideTimer()
    }

    // MARK: - Auto Hide Timer

    private func resetAutoHideTimer() {
        cancelAutoHideTimer()
        guard isPlaying && !isLoading else { return }
        autoHideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.3)) {
                areControlsVisible = false
            }
        }
    }

    private func cancelAutoHideTimer() {
        autoHideTask?.cancel()
        autoHideTask = nil
    }

    private func formatTime(_ seconds: Double) -> String {
        guard !seconds.isNaN, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let s = total % 60
        let m = (total / 60) % 60
        let h = total / 3600

        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%d:%02d", m, s)
        }
    }
}

// MARK: - Custom Scrubber

private struct CustomScrubber: View {
    let progress: Double
    let onScrubStart: () -> Void
    let onScrubChange: (Double) -> Void
    let onScrubEnd: (Double) -> Void

    var body: some View {
        GeometryReader { geo in
            let clampedProgress = max(0, min(1, progress))
            ZStack(alignment: .leading) {
                // Background track
                Capsule()
                    .fill(Color.white.opacity(0.25))
                    .frame(height: 5)

                // Filled track (Always White)
                Capsule()
                    .fill(Color.white)
                    .frame(width: geo.size.width * clampedProgress, height: 5)

                // Scrubber Thumb (Always White)
                Circle()
                    .fill(Color.white)
                    .frame(width: 14, height: 14)
                    .shadow(color: Color.black.opacity(0.3), radius: 3)
                    .offset(x: max(0, min(geo.size.width - 14, (geo.size.width * clampedProgress) - 7)))
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let fraction = max(0, min(1, value.location.x / geo.size.width))
                        onScrubStart()
                        onScrubChange(fraction)
                    }
                    .onEnded { value in
                        let fraction = max(0, min(1, value.location.x / geo.size.width))
                        onScrubEnd(fraction)
                    }
            )
        }
    }
}

// MARK: - Custom Volume Slider

private struct CustomVolumeSlider: View {
    @Binding var volume: Float
    var onEditingChanged: (Bool) -> Void
    var onVolumeChanged: (Float) -> Void

    var body: some View {
        GeometryReader { geo in
            let fraction = CGFloat(max(0, min(1, volume)))
            ZStack(alignment: .leading) {
                // Background track
                Capsule()
                    .fill(Color.white.opacity(0.25))
                    .frame(height: 5)

                // Filled track (Always White)
                Capsule()
                    .fill(Color.white)
                    .frame(width: geo.size.width * fraction, height: 5)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        onEditingChanged(true)
                        let newVol = Float(max(0, min(1, value.location.x / geo.size.width)))
                        volume = newVol
                        onVolumeChanged(newVol)
                    }
                    .onEnded { value in
                        let newVol = Float(max(0, min(1, value.location.x / geo.size.width)))
                        volume = newVol
                        onVolumeChanged(newVol)
                        onEditingChanged(false)
                    }
            )
        }
    }
}
