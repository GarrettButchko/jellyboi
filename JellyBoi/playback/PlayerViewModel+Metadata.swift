//
//  PlayerViewModel+Metadata.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 10/5/26.
//

import UIKit
import AVKit
import CoreMedia
import MediaPlayer
import JellyfinAPI
import LoggingKit
import SDWebImage

extension PlayerViewModel {

    // MARK: - Subtitle Selection

    func selectRequestedSubtitle(in playerItem: AVPlayerItem) async {
        guard let group = try? await playerItem.asset.loadMediaSelectionGroup(for: .legible) else { return }

        if request.subtitleStreamIndex == -1 {
            playerItem.select(nil, in: group)
            AppLogger.debug("Deselected subtitle stream group for item (Subtitles Off)")
            return
        }

        if let subIndex = request.subtitleStreamIndex, subIndex >= 0 {
            let streams = (request.item.mediaStreams ?? []) + (streamContext.mediaSource?.mediaStreams ?? [])
            if let stream = streams.first(where: { $0.type == .subtitle && $0.index == subIndex }) {
                let streamLang = stream.language?.lowercased()
                if let match = group.options.first(where: { opt in
                    if let lang = streamLang, (opt.extendedLanguageTag?.lowercased() == lang || opt.locale?.identifier.lowercased().hasPrefix(lang) == true) {
                        return true
                    }
                    if let title = stream.title, opt.displayName.localizedCaseInsensitiveContains(title) {
                        return true
                    }
                    return false
                }) {
                    playerItem.select(match, in: group)
                    AppLogger.debug("Auto-selected subtitle track: \(match.displayName)")
                }
            }
        }
    }

    // MARK: - Metadata Creation

    func createMetadata(for targetItem: BaseItemDto, artworkData: Data?) -> [AVMetadataItem] {
        var meta: [AVMetadataItem] = []

        let titleText = targetItem.playbackTitle
        let titleItem = AVMutableMetadataItem()
        titleItem.identifier = .commonIdentifierTitle
        titleItem.value = titleText as (NSCopying & NSObjectProtocol)
        titleItem.extendedLanguageTag = "und"
        meta.append(titleItem)

        let subtitleText = targetItem.playbackSubtitle

        if let sub = subtitleText {
            let artistItem = AVMutableMetadataItem()
            artistItem.identifier = .commonIdentifierArtist
            artistItem.value = sub as (NSCopying & NSObjectProtocol)
            artistItem.extendedLanguageTag = "und"
            meta.append(artistItem)

            let trackSubTitleItem = AVMutableMetadataItem()
            trackSubTitleItem.identifier = .iTunesMetadataTrackSubTitle
            trackSubTitleItem.value = sub as (NSCopying & NSObjectProtocol)
            trackSubTitleItem.extendedLanguageTag = "und"
            meta.append(trackSubTitleItem)
        }

        if let overview = targetItem.overview, !overview.isEmpty {
            let descItem = AVMutableMetadataItem()
            descItem.identifier = .commonIdentifierDescription
            descItem.value = overview as (NSCopying & NSObjectProtocol)
            descItem.extendedLanguageTag = "und"
            meta.append(descItem)
        }

        if let genres = targetItem.genres, !genres.isEmpty {
            let genreItem = AVMutableMetadataItem()
            genreItem.identifier = .quickTimeMetadataGenre
            genreItem.value = genres.joined(separator: ", ") as (NSCopying & NSObjectProtocol)
            genreItem.extendedLanguageTag = "und"
            meta.append(genreItem)
        }

        if let rating = targetItem.officialRating, !rating.isEmpty {
            let ratingItem = AVMutableMetadataItem()
            ratingItem.identifier = .iTunesMetadataContentRating
            ratingItem.value = rating as (NSCopying & NSObjectProtocol)
            ratingItem.extendedLanguageTag = "und"
            meta.append(ratingItem)
        }

        if let artworkData {
            let artworkItem = AVMutableMetadataItem()
            artworkItem.identifier = .commonIdentifierArtwork
            artworkItem.dataType = kCMMetadataBaseDataType_JPEG as String
            artworkItem.value = artworkData as (NSCopying & NSObjectProtocol)
            artworkItem.extendedLanguageTag = "und"
            meta.append(artworkItem)
        }

        return meta
    }

    // MARK: - Poster Artwork & Now Playing Info

    func resolveArtworkURLs(for targetItem: BaseItemDto? = nil) -> [URL] {
        let currentItem = targetItem ?? request.item
        return currentItem.artworkURLs(client: client)
    }

    func loadCachedArtwork(for targetItem: BaseItemDto? = nil) -> (Data, UIImage)? {
        let currentItem = targetItem ?? request.item
        let urls = resolveArtworkURLs(for: currentItem)
        guard !urls.isEmpty else { return nil }

        for url in urls {
            let cacheKey = SDWebImageManager.shared.cacheKey(for: url) ?? url.absoluteString
            if let img = SDImageCache.shared.imageFromMemoryCache(forKey: cacheKey) ?? SDImageCache.shared.imageFromDiskCache(forKey: cacheKey) {
                if let data = img.jpegData(compressionQuality: 0.85) ?? img.pngData() {
                    AppLogger.debug("Loaded poster artwork from SDImageCache for \(currentItem.playbackTitle)")
                    return (data, img)
                }
            }
        }

        return nil
    }

    func loadArtwork(for targetItem: BaseItemDto? = nil, timeoutSeconds: Double = 5.0) async -> (Data, UIImage)? {
        let currentItem = targetItem ?? request.item
        if let cached = loadCachedArtwork(for: currentItem) {
            return cached
        }

        let urls = resolveArtworkURLs(for: currentItem)
        guard !urls.isEmpty else { return nil }

        for url in urls {
            if let img = await fetchImage(for: url, timeoutSeconds: timeoutSeconds) {
                if let data = img.jpegData(compressionQuality: 0.85) ?? img.pngData() {
                    AppLogger.debug("Downloaded poster artwork for \(currentItem.playbackTitle)")
                    return (data, img)
                }
            }
        }

        return nil
    }

    nonisolated final class ArtworkFetchBox: @unchecked Sendable {
        private var resumed = false
        private var operation: SDWebImageOperation?
        private let lock = NSLock()

        func setOperation(_ op: SDWebImageOperation?) {
            lock.lock()
            defer { lock.unlock() }
            operation = op
        }

        func resume(with continuation: CheckedContinuation<UIImage?, Never>, image: UIImage?) {
            lock.lock()
            defer { lock.unlock() }
            guard !resumed else { return }
            resumed = true
            operation?.cancel()
            operation = nil
            continuation.resume(returning: image)
        }

        func cancel() {
            lock.lock()
            defer { lock.unlock() }
            operation?.cancel()
            operation = nil
        }
    }

    func fetchImage(for url: URL, timeoutSeconds: Double) async -> UIImage? {
        let fetchBox = ArtworkFetchBox()

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let op = SDWebImageManager.shared.loadImage(
                    with: url,
                    options: [.continueInBackground, .retryFailed, .highPriority],
                    progress: nil
                ) { [weak self] image, _, error, _, _, _ in
                    guard self != nil else {
                        fetchBox.resume(with: continuation, image: nil)
                        return
                    }
                    if let image {
                        fetchBox.resume(with: continuation, image: image)
                    } else {
                        if let error {
                            AppLogger.debug("SDWebImage fetch failed for \(url.lastPathComponent): \(error.localizedDescription)")
                        }
                        fetchBox.resume(with: continuation, image: nil)
                    }
                }
                fetchBox.setOperation(op)

                Task {
                    try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                    fetchBox.resume(with: continuation, image: nil)
                }
            }
        } onCancel: {
            fetchBox.cancel()
        }
    }

    func startAsyncArtworkFetchIfNeeded() {
        guard loadedArtworkImage == nil else { return }
        subscriptions.cancelArtworkTask()
        subscriptions.artworkTask = Task { @MainActor [weak self] in
            guard let self else { return }
            if let (data, img) = await self.loadArtwork(timeoutSeconds: 8.0) {
                guard !Task.isCancelled else { return }
                self.loadedArtworkImage = img
                self.updateNowPlayingInfo(with: img)

                if let currentItem = self.player?.currentItem {
                    var meta = currentItem.externalMetadata
                    meta.removeAll(where: { $0.identifier == .commonIdentifierArtwork })
                    let artworkItem = AVMutableMetadataItem()
                    artworkItem.identifier = .commonIdentifierArtwork
                    artworkItem.dataType = kCMMetadataBaseDataType_JPEG as String
                    artworkItem.value = data as (NSCopying & NSObjectProtocol)
                    artworkItem.extendedLanguageTag = "und"
                    meta.append(artworkItem)
                    currentItem.externalMetadata = meta
                    AppLogger.debug("Attached delayed poster artwork to active playerItem metadata")
                }
            }
        }
    }

    func updateNowPlayingInfo(with artworkImage: UIImage) {
        #if canImport(MediaPlayer)
        var nowPlayingInfo: [String: Any] = [:]
        nowPlayingInfo[MPMediaItemPropertyTitle] = request.item.playbackTitle
        if let sub = request.item.playbackSubtitle {
            nowPlayingInfo[MPMediaItemPropertyArtist] = sub
        }
        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = timeline.durationSeconds
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = timeline.currentSeconds
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = now.isPlaying ? 1.0 : 0.0

        let artwork = MPMediaItemArtwork(boundsSize: artworkImage.size) { _ in artworkImage }
        nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
        AppLogger.debug("Updated MPNowPlayingInfoCenter with title: '\(request.item.playbackTitle)', artist: '\(request.item.playbackSubtitle ?? "nil")', artwork: \(Int(artworkImage.size.width))x\(Int(artworkImage.size.height))")
        #endif
    }
}
