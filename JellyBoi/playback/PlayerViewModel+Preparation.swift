//
//  PlayerViewModel+Preparation.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 10/5/26.
//

import Foundation
import CoreGraphics
import AVKit
import JellyfinAPI
import LoggingKit

/// Turns a `PlaybackRequest` into a ready-to-use `PreparedMedia`.
///
/// This is orchestration only: stream negotiation lives in `PlaybackStreamResolver`, local file
/// handling in `LocalPlaybackItemFactory`, and credentials in `JellyfinAuthorization`.
extension PlayerViewModel {

    // MARK: - Intermediate Preparation Models

    private struct ServerPreparationResult {
        let playerItem: AVPlayerItem
        let playMethod: PlayMethod
        let sessionID: String?
        let selectedSource: MediaSourceInfo?
    }

    // MARK: - Main Media Item Preparation

    func prepareMediaItem(for req: PlaybackRequest) async -> PreparedMedia? {
        guard let itemID = req.item.id else {
            now = .failed(reason: "Invalid media item.")
            AppLogger.error("Failed to prepare playback: Item ID is nil")
            return nil
        }
        guard !Task.isCancelled else { return nil }

        let resumeTicks = applyResumeTicks(for: req)
        var preparedItem: AVPlayerItem?
        var usedLocal = false
        var resolvedPlayMethod: PlayMethod = .directStream
        var sessionID: String?
        var selectedSource: MediaSourceInfo?
        var natSize: CGSize?

        // A local file only ever arrives here already vetted as a natively playable container by
        // `DownloadManager.playableLocalFileURL`; `LocalPlaybackItemFactory` then does the real check.
        if let localURL = req.localFileURL {
            if let localResult = await LocalPlaybackItemFactory.make(
                url: localURL,
                targetAspectRatio: targetAspectRatio
            ) {
                preparedItem = localResult.playerItem
                natSize = localResult.naturalSize
                resolvedPlayMethod = .directPlay
                usedLocal = true
            }
        }

        if !usedLocal, let client {
            if let localURL = req.localFileURL {
                AppLogger.warning("Downloaded file at '\(localURL.path)' is not playable natively offline. Streaming from server instead.")
            }

            guard let serverResult = await prepareServerPlayback(
                for: req,
                itemID: itemID,
                resumeTicks: resumeTicks,
                client: client
            ) else {
                return nil
            }

            preparedItem = serverResult.playerItem
            resolvedPlayMethod = serverResult.playMethod
            sessionID = serverResult.sessionID
            selectedSource = serverResult.selectedSource
        } else if !usedLocal {
            handlePlaybackPreparationFailure(req: req)
            return nil
        }

        guard let playerItem = preparedItem else {
            if case .failed = now {
                // Keep specific failure reason
            } else {
                now = .failed(reason: "Failed to initialize player item.")
            }
            return nil
        }

        return makePreparedMedia(
            req: req,
            playerItem: playerItem,
            sessionID: sessionID,
            selectedSource: selectedSource,
            natSize: natSize,
            playMethod: resolvedPlayMethod
        )
    }

    // MARK: - Resume Position Setup

    private func applyResumeTicks(for req: PlaybackRequest) -> Int {
        let resumeTicks: Int = {
            if req.startFromBeginning { return 0 }
            if timeline.initialResumeTicks > 0 { return timeline.initialResumeTicks }
            return req.item.resumePlaybackTicks
        }()
        if timeline.initialResumeTicks == 0 && resumeTicks > 0 {
            self.timeline.initialResumeTicks = resumeTicks
            self.timeline.currentPositionTicks = resumeTicks
        }
        return resumeTicks
    }

    // MARK: - Server Stream Playback Preparation

    private func prepareServerPlayback(
        for req: PlaybackRequest,
        itemID: String,
        resumeTicks: Int,
        client: JellyfinClient
    ) async -> ServerPreparationResult? {
        let resolver = PlaybackStreamResolver(client: client, userID: userID, request: req)
        let resolution: PlaybackStreamResolver.Resolution
        let resolutionStartedAt = Date()
        do {
            resolution = try await resolver.resolve(itemID: itemID, resumeTicks: resumeTicks)
        } catch is CancellationError {
            // Preparation was abandoned (item changed or view dismissed).
            return nil
        } catch {
            now = .failed(reason: error.localizedDescription)
            return nil
        }
        AppLogger.info("Playback stream resolved in \(String(format: "%.2f", Date().timeIntervalSince(resolutionStartedAt)))s using \(resolution.playMethod)")

        // Apply the token here and only here. The server can return a URL that already carries an
        // `api_key`, and the direct-stream path used to add one too, so this is the single point
        // that decides which token a stream is authenticated with.
        let authenticatedURL = PlaybackURL.applyingAuthentication(resolution.url, token: client.configuration.accessToken)

        // Logged before authentication so the access token never reaches the diagnostics export.
        AppLogger.info("Resolved streaming URL: \(resolution.url.absoluteString)")

        let asset = JellyfinAuthorization.asset(url: authenticatedURL, client: client)
        let playerItem = AVPlayerItem(asset: asset)
        AppLogger.info("Created AVPlayerItem for \(resolution.playMethod); waiting for HLS/player readiness")

        return ServerPreparationResult(
            playerItem: playerItem,
            playMethod: resolution.playMethod,
            sessionID: resolution.sessionID,
            selectedSource: resolution.mediaSource
        )
    }

    // MARK: - Error Handling

    private func handlePlaybackPreparationFailure(req: PlaybackRequest) {
        let reason: String
        if req.localFileURL != nil {
            reason = "The downloaded file could not be opened and server connection is unavailable."
        } else {
            reason = "Server connection is unavailable."
        }
        now = .failed(reason: reason)
        AppLogger.error("Failed to start playback: \(reason)")
    }

    // MARK: - Prepared Media Assembly

    private func makePreparedMedia(
        req: PlaybackRequest,
        playerItem: AVPlayerItem,
        sessionID: String?,
        selectedSource: MediaSourceInfo?,
        natSize: CGSize?,
        playMethod: PlayMethod
    ) -> PreparedMedia {
        let artwork = ArtworkLoader.cached(for: req.item, client: client)
        let meta = createMetadata(for: req.item, artworkData: artwork?.data)
        playerItem.externalMetadata = meta

        let streamCtx = ActiveStreamContext(
            playSessionID: sessionID,
            mediaSourceID: selectedSource?.id,
            mediaSource: selectedSource,
            maxBitrate: req.maxBitrate,
            videoNaturalSize: natSize,
            playMethod: playMethod
        )

        return PreparedMedia(
            request: req,
            playerItem: playerItem,
            streamContext: streamCtx,
            artworkImage: artwork?.image
        )
    }
}
