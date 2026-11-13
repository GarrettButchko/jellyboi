//
//  AudioSessionController.swift
//  JellyBoi
//

import AVFoundation
import LoggingKit

/// Configures the shared `AVAudioSession` for long-form video playback.
///
/// The caller owns the `PlayerViewModel.AudioSessionState` bookkeeping; this utility only performs
/// the session calls and reports whether activation succeeded.
@MainActor
enum AudioSessionController {

    /// Selects the playback category and activates the session.
    ///
    /// `.longFormVideo` is preferred because it tells the system this is video with a stable
    /// timeline. Devices that do not support that policy fall back to plain movie playback.
    static func activateForPlayback() async -> Bool {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, policy: .longFormVideo)
            try await activate()
            AppLogger.debug("Configured AVAudioSession (.playback, .moviePlayback, .longFormVideo)")
            return true
        } catch {
            AppLogger.warning("Long-form video audio session policy failed: \(error.localizedDescription); falling back")
            do {
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
                try await activate()
                return true
            } catch {
                AppLogger.error("Audio session configuration failed: \(error.localizedDescription)", error)
                return false
            }
        }
    }

    /// Releases the session so other apps can resume their audio. Not awaited: cleanup must not
    /// block on the system call.
    static func deactivate() {
        Task.detached {
            do {
                if #available(iOS 27.0, *) {
                    try await AVAudioSession.sharedInstance().deactivate(options: [.notifyOthersOnDeactivation])
                } else {
                    try await Task.detached {
                        try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
                    }.value
                }
            } catch {
                AppLogger.debug("Audio session deactivation info: \(error.localizedDescription)")
            }
        }
    }

    private static func activate() async throws {
        if #available(iOS 27.0, *) {
            try await AVAudioSession.sharedInstance().activate()
        } else {
            try await Task.detached {
                try AVAudioSession.sharedInstance().setActive(true)
            }.value
        }
    }
}
