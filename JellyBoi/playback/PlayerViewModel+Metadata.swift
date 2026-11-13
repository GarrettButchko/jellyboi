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

    func createArtworkMetadataItem(for targetItem: BaseItemDto, preloadedData: Data? = nil) -> AVMetadataItem {
        let artworkData = preloadedData ?? loadCachedArtwork(for: targetItem)?.0
        if let artworkData, !artworkData.isEmpty {
            let item = AVMutableMetadataItem()
            item.identifier = .commonIdentifierArtwork
            item.dataType = artworkData.first == 0x89
                ? (kCMMetadataBaseDataType_PNG as String)
                : (kCMMetadataBaseDataType_JPEG as String)
            item.value = artworkData as NSData
            item.extendedLanguageTag = "und"
            return item
        }

        let template = AVMutableMetadataItem()
        template.identifier = .commonIdentifierArtwork
        template.dataType = kCMMetadataBaseDataType_JPEG as String
        template.extendedLanguageTag = "und"

        return AVMetadataItem(propertiesOf: template) { [weak self] valueRequest in
            Task { @MainActor [weak self] in
                guard let self else {
                    valueRequest.respond(error: NSError(domain: "PlayerMetadata", code: -1, userInfo: [NSLocalizedDescriptionKey: "Player deallocated"]))
                    return
                }
                if let (data, img) = await self.loadArtwork(for: targetItem) {
                    self.artworkState = .loaded(img)
                    valueRequest.respond(value: data as NSData)
                    AppLogger.debug("Fulfilled on-demand artwork metadata for '\(targetItem.playbackTitle)'")
                } else {
                    valueRequest.respond(error: NSError(domain: "PlayerMetadata", code: -2, userInfo: [NSLocalizedDescriptionKey: "Artwork unavailable"]))
                }
            }
        }
    }

    func createMetadata(for targetItem: BaseItemDto, artworkData: Data? = nil) -> [AVMetadataItem] {
        func makeItem(
            _ identifier: AVMetadataIdentifier,
            value: (NSCopying & NSObjectProtocol)?,
            dataType: String? = nil
        ) -> AVMetadataItem? {
            guard let value else { return nil }
            if let string = value as? String, string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return nil
            }
            let item = AVMutableMetadataItem()
            item.identifier = identifier
            item.value = value
            item.extendedLanguageTag = "und"
            if let dataType {
                item.dataType = dataType
            }
            return item
        }

        let titleText = targetItem.playbackTitle
        let subtitleText = targetItem.playbackSubtitle
        let genresText = targetItem.genres?.filter { !$0.isEmpty }.joined(separator: ", ")

        let artworkItem = createArtworkMetadataItem(for: targetItem, preloadedData: artworkData)

        let items: [AVMetadataItem?] = [
            makeItem(.commonIdentifierTitle, value: titleText as NSString),
            makeItem(.commonIdentifierArtist, value: subtitleText as NSString?),
            makeItem(.iTunesMetadataTrackSubTitle, value: subtitleText as NSString?),
            makeItem(.commonIdentifierDescription, value: targetItem.overview as NSString?),
            makeItem(.quickTimeMetadataGenre, value: genresText as NSString?),
            makeItem(.iTunesMetadataContentRating, value: targetItem.officialRating as NSString?),
            artworkItem
        ]

        return items.compactMap { $0 }
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
            if let result = await fetchImage(for: url, timeoutSeconds: timeoutSeconds) {
                AppLogger.debug("Downloaded poster artwork for \(currentItem.playbackTitle)")
                return result
            }
        }

        return nil
    }

    func fetchImage(for url: URL, timeoutSeconds: Double = 5.0) async -> (Data, UIImage)? {
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = timeoutSeconds
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let image = UIImage(data: data) else {
                return nil
            }
            let cacheKey = SDWebImageManager.shared.cacheKey(for: url) ?? url.absoluteString
            await SDImageCache.shared.store(image, imageData: data, forKey: cacheKey, toDisk: true)
            return (data, image)
        } catch {
            AppLogger.debug("Network artwork fetch failed for \(url.lastPathComponent): \(error.localizedDescription)")
            return nil
        }
    }

    func startAsyncArtworkFetchIfNeeded() {
        guard artworkState.image == nil else { return }
        subscriptions.cancelArtworkTask()
        artworkState = .loading
        subscriptions.artworkTask = Task { @MainActor [weak self] in
            guard let self else { return }
            if let (_, img) = await self.loadArtwork(timeoutSeconds: 8.0) {
                guard !Task.isCancelled else { return }
                self.artworkState = .loaded(img)
            } else {
                guard !Task.isCancelled else { return }
                if self.artworkState == .loading {
                    self.artworkState = .none
                }
            }
        }
    }

    func updateNowPlayingInfo(with artworkImage: UIImage? = nil) {
        #if canImport(MediaPlayer)
        var nowPlayingInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        nowPlayingInfo[MPMediaItemPropertyTitle] = request.item.playbackTitle
        if let sub = request.item.playbackSubtitle {
            nowPlayingInfo[MPMediaItemPropertyArtist] = sub
        }
        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = timeline.durationSeconds
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = timeline.currentSeconds
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = now.isPlaying ? 1.0 : 0.0

        if let artworkImage {
            let artwork = MPMediaItemArtwork(boundsSize: artworkImage.size) { _ in artworkImage }
            nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
        AppLogger.debug("Updated MPNowPlayingInfoCenter for '\(request.item.playbackTitle)'")
        #endif
    }
}
