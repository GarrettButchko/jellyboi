//
//  PlayerSubscriptions.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 11/13/26.
//

import Foundation
import AVFoundation

/// Manages player-related observations, timers, and background tasks for unified lifecycle cleanup.
@MainActor
final class PlayerSubscriptions {
    var timeObserverToken: Any?
    var endObserver: NSObjectProtocol?
    var statusObserver: NSKeyValueObservation?
    var muteObserver: NSKeyValueObservation?
    var timeControlStatusObserver: NSKeyValueObservation?
    var artworkTask: Task<Void, Never>?
    var periodicReportTimer: Timer?

    func cancelAll(player: AVPlayer?) {
        cancelPeriodicReporting()
        cancelTimeObserver(player: player)
        cancelEndObserver()
        cancelKVOObservers()
        cancelArtworkTask()
    }

    func cancelPeriodicReporting() {
        periodicReportTimer?.invalidate()
        periodicReportTimer = nil
    }

    func cancelTimeObserver(player: AVPlayer?) {
        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
            timeObserverToken = nil
        }
    }

    func cancelEndObserver() {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
    }

    func cancelKVOObservers() {
        statusObserver?.invalidate()
        statusObserver = nil
        muteObserver?.invalidate()
        muteObserver = nil
        timeControlStatusObserver?.invalidate()
        timeControlStatusObserver = nil
    }

    func cancelArtworkTask() {
        artworkTask?.cancel()
        artworkTask = nil
    }
}
