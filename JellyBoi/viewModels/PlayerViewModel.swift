//
//  PlayerViewModel.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 10/5/26.
//

import SwiftUI
import AVKit
import CoreMedia
import MediaPlayer
import Observation
import Get
import JellyfinAPI
import LoggingKit
import SDWebImage

@Observable
@MainActor
final class PlayerViewModel: Identifiable {

    let id: String = UUID().uuidString
    private(set) var request: PlaybackManager.PlaybackRequest
    let client: JellyfinClient?
    let userID: String?
    weak var libraryViewModel: LibraryViewModel?

    var queue: [BaseItemDto] = []
    var currentIndex: Int = 0

    var player: AVPlayer?
    var isLoading: Bool = true
    var errorMessage: String? = nil
    var isPlaying: Bool = false

    var showUpNextOverlay: Bool = false
    var upNextSecondsRemaining: Int = 0
    var upNextProgressFraction: Double = 0.0
    var areControlsVisible: Bool = true

    private(set) var currentPositionTicks: Int = 0
    private(set) var initialResumeTicks: Int = 0
    private(set) var durationTicks: Int = 0
    private(set) var playSessionID: String?
    private(set) var mediaSourceID: String?
    private(set) var mediaSource: MediaSourceInfo?
    private(set) var maxBitrate: Int?
    private(set) var videoNaturalSize: CGSize?

    private var isPreloadingNext: Bool = false
    private var isSwitchingToNext: Bool = false
    private var isAutoPlayDismissedForCurrentItem: Bool = false
    private var preloadedMedia: PreparedMedia?

    private var timeObserverToken: Any?
    private var endObserver: NSObjectProtocol?
    private var statusObserver: NSKeyValueObservation?
    private var muteObserver: NSKeyValueObservation?
    private var artworkTask: Task<Void, Never>?
    private var loadedArtworkImage: UIImage?
    private var periodicReportTimer: Timer?
    private var hasReportedStart: Bool = false
    private var isCleanedUp: Bool = false
    private var hasAppliedInitialSeek: Bool = false
    private var currentPlayMethod: PlayMethod = .directStream

    private struct PreparedMedia {
        let request: PlaybackManager.PlaybackRequest
        let playerItem: AVPlayerItem
        let mediaSource: MediaSourceInfo?
        let mediaSourceID: String?
        let playSessionID: String?
        let playMethod: PlayMethod
        let artworkImage: UIImage?
        let videoNaturalSize: CGSize?
    }

    init(
        request: PlaybackManager.PlaybackRequest,
        client: JellyfinClient?,
        userID: String?,
        libraryViewModel: LibraryViewModel?,
        queue: [BaseItemDto] = [],
        initialQueueIndex: Int = 0
    ) {
        self.request = request
        self.client = client
        self.userID = userID
        self.libraryViewModel = libraryViewModel
        self.queue = queue
        self.currentIndex = initialQueueIndex
        self.durationTicks = request.item.runTimeTicks.map { Int($0) } ?? 0
        self.mediaSourceID = request.mediaSourceID
        self.maxBitrate = request.maxBitrate
        let resume = request.startFromBeginning ? 0 : request.item.resumePlaybackTicks
        self.initialResumeTicks = resume
        self.currentPositionTicks = resume
        AppLogger.info("Initialized PlayerViewModel for '\(request.item.name ?? "Unknown")' (ID: \(request.item.id ?? "nil"), resumeTicks: \(resume)) [Queue: \(queue.count) items, index: \(initialQueueIndex)]", tag: "Player")
    }

    var item: BaseItemDto {
        request.item
    }

    var nextItem: BaseItemDto? {
        guard currentIndex + 1 < queue.count else { return nil }
        return queue[currentIndex + 1]
    }

    var title: String {
        if item.type == .episode {
            var parts: [String] = []
            if let season = item.parentIndexNumber, let episode = item.indexNumber {
                parts.append("S\(season):E\(episode)")
            }
            if let name = item.name, !name.isEmpty {
                parts.append(name)
            }
            return parts.isEmpty ? (item.name ?? "Episode") : parts.joined(separator: " - ")
        }
        return item.name ?? "Video"
    }

    var subtitle: String? {
        if item.type == .episode {
            return item.seriesName
        }
        if let year = item.productionYear {
            return String(year)
        }
        return nil
    }

    public var targetAspectRatio: Double? {
        let streamAspect = mediaSource?.mediaStreams?.first(where: { $0.type == .video })?.aspectRatio
            ?? item.mediaStreams?.first(where: { $0.type == .video })?.aspectRatio
            ?? item.aspectRatio
            ?? (item.id.flatMap { DownloadManager.shared.downloadItem(for: $0)?.item.mediaStreams?.first(where: { $0.type == .video })?.aspectRatio })
            ?? (item.id.flatMap { DownloadManager.shared.downloadItem(for: $0)?.item.aspectRatio })
        return Self.parseAspectRatio(streamAspect)
    }

    public nonisolated static func parseAspectRatio(_ raw: String?) -> Double? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        if raw.contains(":") {
            let parts = raw.split(separator: ":")
            if parts.count == 2, let num = Double(parts[0]), let den = Double(parts[1]), den > 0 {
                return num / den
            }
        }
        if raw.contains("/") {
            let parts = raw.split(separator: "/")
            if parts.count == 2, let num = Double(parts[0]), let den = Double(parts[1]), den > 0 {
                return num / den
            }
        }
        if let val = Double(raw), val > 0 {
            return val
        }
        return nil
    }

    private static var appleDeviceProfile: DeviceProfile {
        DeviceProfile(
            directPlayProfiles: [
                DirectPlayProfile(
                    audioCodec: "aac,mp3,ac3,eac3,alac,flac",
                    container: "mp4,m4v,mov",
                    type: .video,
                    videoCodec: "h264,hevc"
                ),
                DirectPlayProfile(
                    audioCodec: "aac,mp3,alac,flac,wav",
                    container: "mp3,m4a,aac,flac,wav",
                    type: .audio
                )
            ],
            name: "Apple Native Player",
            subtitleProfiles: [
                SubtitleProfile(format: "vtt", method: .hls),
                SubtitleProfile(format: "webvtt", method: .hls),
                SubtitleProfile(format: "subrip", method: .hls),
                SubtitleProfile(format: "srt", method: .hls),
                SubtitleProfile(format: "ass", method: .encode),
                SubtitleProfile(format: "ssa", method: .encode)
            ],
            transcodingProfiles: [
                TranscodingProfile(
                    protocol: .hls,
                    audioCodec: "aac,mp3,ac3,eac3",
                    container: "mp4",
                    context: .streaming,
                    enableAudioVbrEncoding: true,
                    enableMpegtsM2TsMode: false,
                    enableSubtitlesInManifest: true,
                    isBreakOnNonKeyFrames: true,
                    isCopyTimestamps: true,
                    isEstimateContentLength: false,
                    maxAudioChannels: "6",
                    minSegments: 1,
                    segmentLength: 3,
                    transcodeSeekInfo: .auto,
                    type: .video,
                    videoCodec: "h264,hevc"
                ),
                TranscodingProfile(
                    protocol: .hls,
                    audioCodec: "aac,mp3,ac3,eac3",
                    container: "ts",
                    context: .streaming,
                    enableAudioVbrEncoding: true,
                    enableMpegtsM2TsMode: false,
                    enableSubtitlesInManifest: true,
                    isBreakOnNonKeyFrames: true,
                    isCopyTimestamps: true,
                    isEstimateContentLength: false,
                    maxAudioChannels: "6",
                    minSegments: 1,
                    segmentLength: 3,
                    transcodeSeekInfo: .auto,
                    type: .video,
                    videoCodec: "h264"
                ),
                TranscodingProfile(
                    protocol: .hls,
                    audioCodec: "aac,mp3",
                    container: "mp4",
                    context: .streaming,
                    enableAudioVbrEncoding: true,
                    enableMpegtsM2TsMode: false,
                    enableSubtitlesInManifest: true,
                    isBreakOnNonKeyFrames: true,
                    isCopyTimestamps: true,
                    isEstimateContentLength: false,
                    maxAudioChannels: "6",
                    minSegments: 1,
                    segmentLength: 3,
                    transcodeSeekInfo: .auto,
                    type: .audio
                )
            ]
        )
    }

    private func resolveServerURL(path: String, client: JellyfinClient) -> URL? {
        if path.hasPrefix("http://") || path.hasPrefix("https://") {
            return URL(string: path)
        }
        return client.url(path: path)
    }

    private func authorizationHeader(for client: JellyfinClient) -> String {
        var rawFields = [
            "DeviceId": client.configuration.deviceID,
            "Device": client.configuration.deviceName,
            "Client": client.configuration.client,
            "Version": client.configuration.version,
        ]
        if let token = client.configuration.accessToken {
            rawFields["Token"] = token
        }
        let fields = rawFields.map { "\($0.key)=\"\($0.value)\"" }.joined(separator: ", ")
        return "MediaBrowser \(fields)"
    }

    private func resolveQueueIfNeeded() async {
        guard queue.isEmpty, let client else { return }
        if item.type == .episode, let seriesID = item.seriesID {
            AppLogger.info("Resolving queue for series '\(item.seriesName ?? seriesID)'", tag: "Player")
            let cached = (libraryViewModel?.episodes ?? [])
                .filter { $0.seriesID == seriesID }
                .sorted { a, b in
                    let sA = a.parentIndexNumber ?? 1
                    let sB = b.parentIndexNumber ?? 1
                    if sA != sB { return sA < sB }
                    return (a.indexNumber ?? 1) < (b.indexNumber ?? 1)
                }

            if !cached.isEmpty {
                self.queue = cached
                if let idx = cached.firstIndex(where: { $0.id == item.id }) {
                    self.currentIndex = idx
                }
                return
            }

            let result = await client.fetchEpisodesOrEmpty(seriesID: seriesID, userID: userID)
            if !result.isEmpty {
                let sorted = result.sorted { a, b in
                    let sA = a.parentIndexNumber ?? 1
                    let sB = b.parentIndexNumber ?? 1
                    if sA != sB { return sA < sB }
                    return (a.indexNumber ?? 1) < (b.indexNumber ?? 1)
                }
                self.queue = sorted
                if let idx = sorted.firstIndex(where: { $0.id == item.id }) {
                    self.currentIndex = idx
                }
            }
        }
    }

    func prepare() async -> Bool {
        guard !isCleanedUp else {
            AppLogger.warning("Aborted player preparation: already cleaned up", tag: "Player")
            return false
        }
        isLoading = true
        errorMessage = nil
        hasAppliedInitialSeek = false
        AppLogger.info("Starting player preparation for '\(title)'", tag: "Player")

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, policy: .longFormVideo)
            try await activateAudioSession()
            AppLogger.debug("Configured AVAudioSession (.playback, .moviePlayback, .longFormVideo)", tag: "Player")
        } catch {
            AppLogger.warning("Long-form video audio session policy failed: \(error.localizedDescription); falling back", tag: "Player")
            do {
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
                try await activateAudioSession()
            } catch {
                AppLogger.error("Audio session configuration failed: \(error.localizedDescription)", error, tag: "Player")
            }
        }

        await resolveQueueIfNeeded()

        guard let prepared = await prepareMediaItem(for: request) else {
            isLoading = false
            return false
        }

        self.mediaSource = prepared.mediaSource
        self.mediaSourceID = prepared.mediaSourceID
        self.playSessionID = prepared.playSessionID
        self.currentPlayMethod = prepared.playMethod
        self.loadedArtworkImage = prepared.artworkImage
        self.videoNaturalSize = prepared.videoNaturalSize

        let avPlayer = AVPlayer(playerItem: prepared.playerItem)
        avPlayer.allowsExternalPlayback = true
        avPlayer.usesExternalPlaybackWhileExternalScreenIsActive = true
        self.player = avPlayer

        startAsyncArtworkFetchIfNeeded()

        var lastNonZeroVolume: Float = 1.0
        muteObserver = avPlayer.observe(\.isMuted, options: [.new]) { player, _ in
            if player.isMuted {
                if player.volume > 0.0 {
                    lastNonZeroVolume = player.volume
                }
                player.isMuted = false
                player.volume = lastNonZeroVolume > 0.0 ? lastNonZeroVolume : 1.0
            }
        }

        timeObserverToken = avPlayer.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 4),
            queue: .main
        ) { [weak self] time in
            guard let self else { return }
            MainActor.assumeIsolated {
                let seconds = CMTimeGetSeconds(time)
                if seconds.isFinite && seconds >= 0 {
                    if self.hasAppliedInitialSeek || self.initialResumeTicks == 0 {
                        self.currentPositionTicks = Int(seconds * 10_000_000.0)
                    }
                }
                if let dur = avPlayer.currentItem?.duration {
                    let durationSec = CMTimeGetSeconds(dur)
                    if durationSec.isFinite && durationSec > 0 {
                        self.durationTicks = Int(durationSec * 10_000_000.0)
                        if !self.hasAppliedInitialSeek && self.initialResumeTicks == 0 && !self.request.startFromBeginning {
                            if let percent = self.request.item.userData?.playedPercentage, percent > 0 {
                                let calculated = Int((Double(self.durationTicks) * percent) / 100.0)
                                self.initialResumeTicks = calculated
                                self.currentPositionTicks = calculated
                            }
                        }
                    }
                }
                self.checkUpNextTrigger(currentSeconds: seconds)
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: prepared.playerItem,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                AppLogger.info("Playback reached end of media item", tag: "Player")
                self?.handlePlaybackFinished()
            }
        }

        let isReady = await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                await self.waitForReadiness(playerItem: prepared.playerItem)
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(30))
                return false
            }
            let firstResult = await group.next() ?? false
            group.cancelAll()
            return firstResult
        }

        if !isReady && errorMessage == nil {
            errorMessage = "Playback connection timed out. Please try again."
        }
        return isReady
    }

    private func prepareMediaItem(for req: PlaybackManager.PlaybackRequest) async -> PreparedMedia? {
        guard let itemID = req.item.id else {
            errorMessage = "Invalid media item."
            AppLogger.error("Failed to prepare playback: Item ID is nil", tag: "Player")
            return nil
        }

        let resumeTicks: Int = {
            if req.startFromBeginning { return 0 }
            if initialResumeTicks > 0 { return initialResumeTicks }
            return req.item.resumePlaybackTicks
        }()
        if initialResumeTicks == 0 && resumeTicks > 0 {
            self.initialResumeTicks = resumeTicks
            self.currentPositionTicks = resumeTicks
        }
        var preparedItem: AVPlayerItem?
        var usedLocal = false
        var resolvedPlayMethod: PlayMethod = .directStream
        var sessionID: String?
        var selectedSource: MediaSourceInfo?
        var natSize: CGSize?

        let isLocalPlayable = req.localFileURL.map { url in
            let ext = url.pathExtension.lowercased()
            return ["mp4", "m4v", "mov"].contains(ext)
        } ?? false

        if let localURL = req.localFileURL, isLocalPlayable {
            let asset = AVURLAsset(url: localURL)
            let isPlayable = (try? await asset.load(.isPlayable)) ?? false
            if isPlayable {
                AppLogger.info("Preparing local file playback from: \(localURL.path)", tag: "Player")
                let pItem = AVPlayerItem(asset: asset)

                if let tracks = try? await asset.loadTracks(withMediaType: .video),
                   let videoTrack = tracks.first,
                   let naturalSize = try? await videoTrack.load(.naturalSize),
                   naturalSize.width > 0, naturalSize.height > 0 {
                    natSize = naturalSize
                    let trackDAR = naturalSize.width / naturalSize.height
                    if let targetDAR = self.targetAspectRatio, abs(trackDAR - targetDAR) / targetDAR > 0.02 {
                        let preferredTransform = (try? await videoTrack.load(.preferredTransform)) ?? .identity
                        let renderWidth = naturalSize.height * targetDAR
                        let renderHeight = naturalSize.height
                        let scaleX = renderWidth / naturalSize.width

                        var layerConfig = AVVideoCompositionLayerInstruction.Configuration(assetTrack: videoTrack)
                        let adjustedTransform = preferredTransform.scaledBy(x: scaleX, y: 1.0)
                        layerConfig.setTransform(adjustedTransform, at: .zero)
                        let layerInstruction = AVVideoCompositionLayerInstruction(configuration: layerConfig)

                        var instructionConfig = AVVideoCompositionInstruction.Configuration()
                        instructionConfig.timeRange = CMTimeRange(start: .zero, duration: .positiveInfinity)
                        instructionConfig.layerInstructions = [layerInstruction]
                        let instruction = AVVideoCompositionInstruction(configuration: instructionConfig)

                        var compositionConfig = AVVideoComposition.Configuration()
                        compositionConfig.instructions = [instruction]
                        compositionConfig.renderSize = CGSize(width: renderWidth, height: renderHeight)
                        let nominalFrameRate = (try? await videoTrack.load(.nominalFrameRate)) ?? 0
                        let fps = nominalFrameRate > 0 ? Int32(round(nominalFrameRate)) : 30
                        compositionConfig.frameDuration = CMTime(value: 1, timescale: fps)

                        let composition = AVVideoComposition(configuration: compositionConfig)
                        pItem.videoComposition = composition
                    }
                }

                preparedItem = pItem
                resolvedPlayMethod = .directPlay
                usedLocal = true
            } else {
                AppLogger.warning("Local file at \(localURL.path) cannot be opened by AVPlayer. Falling back to server stream.", tag: "Player")
            }
        }

        if !usedLocal, let client {
            if let localURL = req.localFileURL {
                AppLogger.warning("Downloaded file at '\(localURL.path)' is not playable natively offline. Streaming from server instead.", tag: "Player")
            }
            var streamURL: URL?

            let targetBitrate: Int? = req.maxBitrate
            let allowDirect = req.maxBitrate == nil
            let subIndex = req.subtitleStreamIndex
            let playbackDto = PlaybackInfoDto(
                allowAudioStreamCopy: true,
                allowVideoStreamCopy: allowDirect,
                audioStreamIndex: req.audioStreamIndex,
                deviceProfile: Self.appleDeviceProfile,
                enableDirectPlay: allowDirect,
                enableDirectStream: allowDirect,
                enableTranscoding: true,
                maxStreamingBitrate: targetBitrate,
                mediaSourceID: req.mediaSourceID,
                startTimeTicks: resumeTicks,
                subtitleStreamIndex: subIndex,
                userID: userID
            )

            do {
                let playbackInfo = try await client.send(
                    Paths.getPostedPlaybackInfo(
                        itemID: itemID,
                        parameters: .init(userID: userID, maxStreamingBitrate: targetBitrate),
                        playbackDto
                    )
                ).value
                sessionID = playbackInfo.playSessionID

                let matchingSource = playbackInfo.mediaSources?.first(where: { $0.id == req.mediaSourceID })
                    ?? playbackInfo.mediaSources?.first

                if let first = matchingSource {
                    selectedSource = first
                    if let transURL = first.transcodingURL, !transURL.isEmpty {
                        resolvedPlayMethod = (req.maxBitrate != nil) ? .transcode : ((first.isSupportsDirectStream == true && first.isSupportsTranscoding != true) ? .directStream : .transcode)
                        var fullTransURL = transURL
                        if let maxBitrate = req.maxBitrate, !fullTransURL.contains("MaxStreamingBitrate=") {
                            let sep = fullTransURL.contains("?") ? "&" : "?"
                            fullTransURL += "\(sep)VideoBitRate=\(maxBitrate)&MaxStreamingBitrate=\(maxBitrate)"
                        }
                        streamURL = resolveServerURL(path: fullTransURL, client: client)
                        AppLogger.info("Using server-provided transcoding URL: \(streamURL?.absoluteString ?? fullTransURL)", tag: "Player")
                    }
                }
            } catch {
                AppLogger.warning("Failed to get posted playback info: \(error.localizedDescription)", tag: "Player")
            }

            if streamURL == nil {
                let container = selectedSource?.container?.lowercased() ?? ""
                let isAppleNativeContainer = ["mp4", "m4v", "mov"].contains(container)
                let hasCustomStreams = req.audioStreamIndex != nil || (req.subtitleStreamIndex != nil && req.subtitleStreamIndex! >= 0) || req.maxBitrate != nil
                let canDirectPlay = selectedSource?.isSupportsDirectPlay == true && isAppleNativeContainer && !hasCustomStreams

                if canDirectPlay {
                    resolvedPlayMethod = .directPlay
                    AppLogger.info("Media container is '\(container)'; using direct static stream", tag: "Player")
                    streamURL = client.directVideoStreamURL(
                        itemID: itemID,
                        sessionID: sessionID,
                        mediaSourceID: selectedSource?.id
                    )
                } else {
                    resolvedPlayMethod = (req.maxBitrate != nil) ? .transcode : .directStream
                    AppLogger.info("Container '\(container)' requires HLS remuxing/transcoding for AVPlayer; requesting master.m3u8", tag: "Player")
                    let sourceID = selectedSource?.id ?? req.mediaSourceID ?? itemID
                    let sid = sessionID ?? UUID().uuidString
                    sessionID = sid
                    var hlsPath = "/Videos/\(itemID)/master.m3u8?MediaSourceId=\(sourceID)&PlaySessionId=\(sid)&VideoCodec=h264,hevc&AudioCodec=aac,mp3,ac3,eac3&TranscodingMaxAudioChannels=6&SegmentContainer=mp4&MinSegments=1&BreakOnNonKeyFrames=True&StartTimeTicks=\(resumeTicks)"
                    if let audioIndex = req.audioStreamIndex {
                        hlsPath += "&AudioStreamIndex=\(audioIndex)"
                    }
                    if let subtitleIndex = req.subtitleStreamIndex {
                        hlsPath += "&SubtitleStreamIndex=\(subtitleIndex)"
                    }
                    if let maxBitrate = req.maxBitrate {
                        hlsPath += "&VideoBitRate=\(maxBitrate)&MaxStreamingBitrate=\(maxBitrate)"
                    }
                    streamURL = resolveServerURL(path: hlsPath, client: client)
                }
            }

            guard var url = streamURL else {
                errorMessage = "Unable to construct stream URL."
                AppLogger.error("Failed to construct stream URL for item \(itemID)", tag: "Player")
                return nil
            }

            if let token = client.configuration.accessToken,
               var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                var queryItems = components.queryItems ?? []
                if !queryItems.contains(where: { $0.name == "api_key" }) {
                    queryItems.append(URLQueryItem(name: "api_key", value: token))
                    components.queryItems = queryItems
                    if let updatedURL = components.url {
                        url = updatedURL
                    }
                }
            }

            AppLogger.info("Resolved streaming URL: \(url.absoluteString)", tag: "Player")
            var headers: [String: String] = [
                "Authorization": authorizationHeader(for: client)
            ]
            if let token = client.configuration.accessToken {
                headers["X-Emby-Token"] = token
            }

            let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
            preparedItem = AVPlayerItem(asset: asset)
        } else if !usedLocal {
            if let localURL = req.localFileURL, !isLocalPlayable {
                errorMessage = "This video is downloaded in .\(localURL.pathExtension.uppercased()) format, which iOS cannot play offline. Please connect to your server to stream or re-download as MP4."
            } else if req.localFileURL != nil {
                errorMessage = "The downloaded file could not be opened and server connection is unavailable."
            } else {
                errorMessage = "Server connection is unavailable."
            }
            AppLogger.error("Failed to start playback: \(errorMessage ?? "")", tag: "Player")
            return nil
        }

        guard let playerItem = preparedItem else {
            errorMessage = "Failed to initialize player item."
            return nil
        }

        let artwork = await loadArtwork(for: req.item)
        let meta = createMetadata(for: req.item, artworkData: artwork?.0)
        playerItem.externalMetadata = meta

        return PreparedMedia(
            request: req,
            playerItem: playerItem,
            mediaSource: selectedSource,
            mediaSourceID: selectedSource?.id,
            playSessionID: sessionID,
            playMethod: resolvedPlayMethod,
            artworkImage: artwork?.1,
            videoNaturalSize: natSize
        )
    }

    private func createMetadata(for targetItem: BaseItemDto, artworkData: Data?) -> [AVMetadataItem] {
        var meta: [AVMetadataItem] = []

        let titleText: String = {
            if targetItem.type == .episode {
                var parts: [String] = []
                if let season = targetItem.parentIndexNumber, let episode = targetItem.indexNumber {
                    parts.append("S\(season):E\(episode)")
                }
                if let name = targetItem.name, !name.isEmpty {
                    parts.append(name)
                }
                return parts.isEmpty ? (targetItem.name ?? "Episode") : parts.joined(separator: " - ")
            }
            return targetItem.name ?? "Video"
        }()

        let titleItem = AVMutableMetadataItem()
        titleItem.identifier = .commonIdentifierTitle
        titleItem.value = titleText as (NSCopying & NSObjectProtocol)
        titleItem.extendedLanguageTag = "und"
        meta.append(titleItem)

        let subtitleText: String? = {
            if targetItem.type == .episode {
                return targetItem.seriesName
            }
            if let year = targetItem.productionYear {
                return String(year)
            }
            return nil
        }()

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

    // MARK: - Up Next & In-Place Progression

    private func checkUpNextTrigger(currentSeconds: Double) {
        guard let dur = player?.currentItem?.duration else { return }
        let durationSec = CMTimeGetSeconds(dur)
        guard durationSec.isFinite && durationSec > 60 else { return }

        let remainingSec = durationSec - currentSeconds

        guard nextItem != nil else {
            if showUpNextOverlay {
                showUpNextOverlay = false
        upNextSecondsRemaining = 0
        upNextProgressFraction = 0.0
            }
            return
        }

        if remainingSec <= 30 && remainingSec >= 0 {
            upNextSecondsRemaining = max(0, Int(round(remainingSec)))
            upNextProgressFraction = max(0.0, min(1.0, (30.0 - remainingSec) / 30.0))

            if !isAutoPlayDismissedForCurrentItem && !showUpNextOverlay {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                    showUpNextOverlay = true
                }
            }

            if preloadedMedia == nil && !isPreloadingNext {
                Task {
                    await preloadNextMedia()
                }
            }
        } else {
            if showUpNextOverlay {
                withAnimation(.easeInOut(duration: 0.25)) {
                    showUpNextOverlay = false
                }
            }
        }
    }

    func dismissUpNextOverlay() {
        withAnimation(.easeInOut(duration: 0.25)) {
            showUpNextOverlay = false
            upNextSecondsRemaining = 0
            upNextProgressFraction = 0.0
        }
        isAutoPlayDismissedForCurrentItem = true
    }

    private func preloadNextMedia() async {
        guard let next = nextItem, !isPreloadingNext, preloadedMedia == nil else { return }
        isPreloadingNext = true
        defer { isPreloadingNext = false }

        AppLogger.info("Preloading next media item: '\(next.name ?? "Unknown")'", tag: "Player")

        let resolvedLocalURL: URL? = {
            #if DEBUG
            if DebugSettings.shared.forceStreamFallback { return nil }
            #endif
            guard let id = next.id, DownloadManager.shared.isLocallyPlayable(id: id) else { return nil }
            return DownloadManager.shared.localFileURL(for: id)
        }()

        let nextReq = PlaybackManager.PlaybackRequest(
            item: next,
            startFromBeginning: true,
            localFileURL: resolvedLocalURL
        )

        if let prepared = await prepareMediaItem(for: nextReq) {
            self.preloadedMedia = prepared
            AppLogger.success("Successfully preloaded next item: '\(next.name ?? "Unknown")'", tag: "Player")
        }
    }

    func playNextItem() async {
        guard let next = nextItem, !isSwitchingToNext else { return }
        isSwitchingToNext = true
        defer { isSwitchingToNext = false }

        AppLogger.info("Transitioning to next item: '\(next.name ?? "Unknown")'", tag: "Player")

        handlePlaybackFinished(isSwitchingToNext: true)

        withAnimation(.easeInOut(duration: 0.25)) {
            showUpNextOverlay = false
        }
        isAutoPlayDismissedForCurrentItem = false

        let mediaToPlay: PreparedMedia
        if let preloaded = preloadedMedia, preloaded.request.item.id == next.id {
            mediaToPlay = preloaded
            preloadedMedia = nil
            AppLogger.info("Using preloaded player item for '\(next.name ?? "Unknown")'", tag: "Player")
        } else {
            isLoading = true
            let resolvedLocalURL: URL? = {
                #if DEBUG
                if DebugSettings.shared.forceStreamFallback { return nil }
                #endif
                guard let id = next.id, DownloadManager.shared.isLocallyPlayable(id: id) else { return nil }
                return DownloadManager.shared.localFileURL(for: id)
            }()
            let nextReq = PlaybackManager.PlaybackRequest(
                item: next,
                startFromBeginning: true,
                localFileURL: resolvedLocalURL
            )
            guard let newlyPrepared = await prepareMediaItem(for: nextReq) else {
                isLoading = false
                AppLogger.error("Failed to prepare next item for playback", tag: "Player")
                return
            }
            mediaToPlay = newlyPrepared
            isLoading = false
        }

        self.request = mediaToPlay.request
        self.durationTicks = mediaToPlay.request.item.runTimeTicks.map { Int($0) } ?? 0
        let nextResume = mediaToPlay.request.startFromBeginning ? 0 : mediaToPlay.request.item.resumePlaybackTicks
        self.initialResumeTicks = nextResume
        self.currentPositionTicks = nextResume
        self.mediaSource = mediaToPlay.mediaSource
        self.mediaSourceID = mediaToPlay.mediaSourceID
        self.playSessionID = mediaToPlay.playSessionID
        self.currentPlayMethod = mediaToPlay.playMethod
        self.loadedArtworkImage = mediaToPlay.artworkImage
        self.videoNaturalSize = mediaToPlay.videoNaturalSize
        self.hasReportedStart = false
        self.hasAppliedInitialSeek = false
        self.currentIndex += 1

        player?.replaceCurrentItem(with: mediaToPlay.playerItem)

        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: mediaToPlay.playerItem,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                AppLogger.info("Playback reached end of media item", tag: "Player")
                self?.handlePlaybackFinished()
            }
        }

        if let img = loadedArtworkImage {
            updateNowPlayingInfo(with: img)
        }

        await selectRequestedSubtitle(in: mediaToPlay.playerItem)

        if !self.hasAppliedInitialSeek && self.initialResumeTicks > 0 {
            self.hasAppliedInitialSeek = true
            let seconds = Double(self.initialResumeTicks) / 10_000_000.0
            let currentSec = CMTimeGetSeconds(self.player?.currentTime() ?? .zero)
            if abs(currentSec - seconds) > 2.0 {
                AppLogger.info("Seeking queue item to resume position: \(String(format: "%.1f", seconds))s (ticks: \(self.initialResumeTicks))", tag: "Player")
                let targetTime = CMTime(seconds: seconds, preferredTimescale: 600)
                await self.player?.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero)
            }
            self.currentPositionTicks = self.initialResumeTicks
        } else {
            self.hasAppliedInitialSeek = true
        }

        player?.play()
        isPlaying = true
        hasReportedStart = true
        await reportPlaybackStart()
        startPeriodicReporting()
        AppLogger.success("Now playing next item: '\(title)'", tag: "Player")
    }

    private nonisolated final class ReadinessBox: @unchecked Sendable {
        private var resumed = false
        private var resumeClosure: ((Bool) -> Void)?
        private let lock = NSLock()

        func setResume(_ closure: @escaping (Bool) -> Void) {
            lock.lock()
            defer { lock.unlock() }
            resumeClosure = closure
        }

        func resume(returning value: Bool) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard !resumed, let closure = resumeClosure else { return false }
            resumed = true
            resumeClosure = nil
            closure(value)
            return true
        }
    }

    private func waitForReadiness(playerItem: AVPlayerItem) async -> Bool {
        if playerItem.status == .readyToPlay {
            await applyReadyToPlay()
            return true
        }
        if playerItem.status == .failed {
            let err = playerItem.error?.localizedDescription ?? "Playback failed."
            self.errorMessage = err
            return false
        }

        let box = ReadinessBox()

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                box.setResume { val in
                    continuation.resume(returning: val)
                }

                statusObserver = playerItem.observe(\.status, options: [.initial, .new]) { [weak self] currentItem, _ in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        switch currentItem.status {
                        case .readyToPlay:
                            if box.resume(returning: true) {
                                AppLogger.success("PlayerItem is readyToPlay.", tag: "Player")
                                await self.applyReadyToPlay()
                            }

                        case .failed:
                            if box.resume(returning: false) {
                                let err = currentItem.error?.localizedDescription ?? "Playback failed."
                                AppLogger.error("PlayerItem failed with error: \(err)", tag: "Player")
                                if let log = currentItem.errorLog() {
                                    for event in log.events {
                                        AppLogger.error("AVPlayerItem error event: URI=\(event.uri ?? "nil"), status=\(event.errorStatusCode), domain=\(event.errorDomain), comment=\(event.errorComment ?? "nil")", tag: "Player")
                                    }
                                }
                                self.isLoading = false
                                self.errorMessage = err
                            }

                        case .unknown:
                            break
                        @unknown default:
                            break
                        }
                    }
                }
            }
        } onCancel: {
            _ = box.resume(returning: false)
        }
    }

    private func applyReadyToPlay() async {
        self.isLoading = false
        if let current = self.player?.currentItem {
            let tracks = current.tracks
            let trackInfo = tracks.map { track -> String in
                let mediaType = track.assetTrack?.mediaType.rawValue ?? "unknown"
                return "\(mediaType) (isEnabled: \(track.isEnabled))"
            }
            AppLogger.info("PlayerItem ready with \(tracks.count) tracks: [\(trackInfo.joined(separator: ", "))]", tag: "Player")

            let videoTracks = tracks.filter { $0.assetTrack?.mediaType == .video }
            if videoTracks.isEmpty {
                AppLogger.warning("PlayerItem has NO video tracks active. PresentationSize: \(current.presentationSize)", tag: "Player")
            } else {
                for vt in videoTracks {
                    let size = (try? await vt.assetTrack?.load(.naturalSize)) ?? .zero
                    AppLogger.debug("Video track enabled: \(vt.isEnabled), size: \(size.width)x\(size.height)", tag: "Player")
                }
            }

            if self.videoNaturalSize == nil, let firstVideoTrack = videoTracks.compactMap({ $0.assetTrack }).first {
                if let size = try? await firstVideoTrack.load(.naturalSize), size.width > 0, size.height > 0 {
                    self.videoNaturalSize = size
                }
            }

            await selectRequestedSubtitle(in: current)
        }
        if !self.hasAppliedInitialSeek && self.initialResumeTicks > 0 {
            self.hasAppliedInitialSeek = true
            let seconds = Double(self.initialResumeTicks) / 10_000_000.0
            let currentSec = CMTimeGetSeconds(self.player?.currentTime() ?? .zero)
            if abs(currentSec - seconds) > 2.0 {
                AppLogger.info("Seeking to resume position: \(String(format: "%.1f", seconds))s (ticks: \(self.initialResumeTicks))", tag: "Player")
                let targetTime = CMTime(seconds: seconds, preferredTimescale: 600)
                await self.player?.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero)
            }
            self.currentPositionTicks = self.initialResumeTicks
        } else {
            self.hasAppliedInitialSeek = true
        }
        self.player?.play()
        self.isPlaying = true
        if let img = loadedArtworkImage {
            updateNowPlayingInfo(with: img)
        }
        if !self.hasReportedStart {
            self.hasReportedStart = true
            await self.reportPlaybackStart()
            self.startPeriodicReporting()
        }
    }

    // MARK: - Subtitle Selection

    private func selectRequestedSubtitle(in playerItem: AVPlayerItem) async {
        guard let group = try? await playerItem.asset.loadMediaSelectionGroup(for: .legible) else { return }

        if request.subtitleStreamIndex == -1 {
            playerItem.select(nil, in: group)
            AppLogger.debug("Deselected subtitle stream group for item (Subtitles Off)", tag: "Player")
            return
        }

        if let subIndex = request.subtitleStreamIndex, subIndex >= 0 {
            let streams = (request.item.mediaStreams ?? []) + (mediaSource?.mediaStreams ?? [])
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
                    AppLogger.debug("Auto-selected subtitle track: \(match.displayName)", tag: "Player")
                }
            }
        }
    }

    // MARK: - Periodic Reporting

    private func startPeriodicReporting() {
        periodicReportTimer?.invalidate()
        periodicReportTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.reportPlaybackProgress()
            }
        }
    }

    func reportPlaybackStart() async {
        guard let client, let itemID = item.id else { return }
        AppLogger.debug("Reporting playback start to Jellyfin (positionTicks: \(currentPositionTicks), method: \(currentPlayMethod.rawValue))", tag: "Player")
        let state = PlaybackStateInfo(
            canSeek: true,
            isPaused: false,
            itemID: itemID,
            mediaSourceID: mediaSourceID,
            playMethod: currentPlayMethod,
            playSessionID: playSessionID,
            positionTicks: currentPositionTicks
        )
        do {
            try await client.reportPlaybackStart(state)
            AppLogger.debug("Successfully reported playback start", tag: "Player")
        } catch {
            AppLogger.warning("Failed to report playback start: \(error.localizedDescription)", tag: "Player")
        }
    }

    func reportPlaybackProgress() async {
        guard let client, let itemID = item.id else { return }
        let isPaused = player?.timeControlStatus == .paused
        let currentSeconds = Double(currentPositionTicks) / 10_000_000.0
        let totalSeconds = Double(durationTicks) / 10_000_000.0
        let percent = totalSeconds > 0 ? (currentSeconds / totalSeconds) * 100 : 0
        AppLogger.debug("Progress report: \(String(format: "%.1f", currentSeconds))s / \(String(format: "%.1f", totalSeconds))s (\(String(format: "%.1f", percent))%) [paused: \(isPaused)]", tag: "Player")

        let state = PlaybackStateInfo(
            canSeek: true,
            isPaused: isPaused,
            itemID: itemID,
            mediaSourceID: mediaSourceID,
            playMethod: currentPlayMethod,
            playSessionID: playSessionID,
            positionTicks: currentPositionTicks
        )
        do {
            try await client.reportPlaybackProgress(state)
        } catch {
            AppLogger.warning("Failed to report playback progress: \(error.localizedDescription)", tag: "Player")
        }
        updateLocalProgress(positionTicks: currentPositionTicks)
    }

    func reportPlaybackStopped() async {
        guard let client, let itemID = item.id else { return }
        AppLogger.info("Reporting playback stopped to Jellyfin (final positionTicks: \(currentPositionTicks))", tag: "Player")
        let stopInfo = PlaybackStopInfo(
            itemID: itemID,
            mediaSourceID: mediaSourceID,
            playSessionID: playSessionID,
            positionTicks: currentPositionTicks
        )
        do {
            try await client.reportPlaybackStopped(stopInfo)
            AppLogger.debug("Successfully reported playback stop to server", tag: "Player")
        } catch {
            AppLogger.warning("Failed to report playback stop: \(error.localizedDescription)", tag: "Player")
        }
    }

    private func handlePlaybackFinished(isSwitchingToNext: Bool = false) {
        let finalTicks = durationTicks > 0 ? durationTicks : currentPositionTicks
        currentPositionTicks = finalTicks
        AppLogger.success("Playback marked as watched (100%)", tag: "Player")
        updateLocalProgress(positionTicks: finalTicks, forcePlayed: true)
        if hasReportedStart, let client, let itemID = item.id {
            let sessionID = playSessionID
            let sourceID = mediaSourceID
            Task.detached {
                let stopInfo = PlaybackStopInfo(
                    itemID: itemID,
                    mediaSourceID: sourceID,
                    playSessionID: sessionID,
                    positionTicks: finalTicks
                )
                _ = try? await client.reportPlaybackStopped(stopInfo)
            }
        }

        if !isSwitchingToNext {
            if nextItem != nil {
                Task { @MainActor [weak self] in
                    await self?.playNextItem()
                }
            } else {
                AppLogger.info("Final item in queue completed. Dismissing player.", tag: "Player")
                PlaybackManager.shared.stop()
            }
        }
    }

    private func updateLocalProgress(positionTicks: Int, forcePlayed: Bool = false) {
        guard let itemID = item.id else { return }
        let total = durationTicks > 0 ? durationTicks : (item.runTimeTicks.map { Int($0) } ?? 0)
        let percent: Double = total > 0 ? (Double(positionTicks) / Double(total)) * 100.0 : 0.0
        let isPlayed = forcePlayed || percent >= 85.0

        libraryViewModel?.updateProgress(for: itemID, positionTicks: positionTicks, totalTicks: total)

        NotificationCenter.default.post(
            name: .mediaProgressUpdated,
            object: itemID,
            userInfo: [
                "positionTicks": positionTicks,
                "durationTicks": total,
                "playedPercentage": percent,
                "isPlayed": isPlayed
            ]
        )
    }

    // MARK: - Poster Artwork & Now Playing Info

    private func resolveArtworkURLs(for targetItem: BaseItemDto? = nil) -> [URL] {
        guard let client else { return [] }
        var urls: [URL] = []
        let currentItem = targetItem ?? request.item

        // 1. LibraryViewModel posterURL (matches the card / detail cache key)
        if let libURL = libraryViewModel?.posterURL(for: currentItem, client: client) {
            urls.append(libURL)
        }

        // 2. Primary image
        if let id = currentItem.id {
            if let primaryURL = client.itemImageURL(
                itemID: id,
                parameters: .detailPoster()
            ) {
                if !urls.contains(primaryURL) {
                    urls.append(primaryURL)
                }
            }
        }

        // 3. For episodes, fallback to series or season poster
        if currentItem.type == .episode {
            if let seriesID = currentItem.seriesID {
                if let seriesURL = client.itemImageURL(
                    itemID: seriesID,
                    parameters: .detailPoster()
                ) {
                    if !urls.contains(seriesURL) {
                        urls.append(seriesURL)
                    }
                }
            }
            if let seasonID = currentItem.seasonID {
                if let seasonURL = client.itemImageURL(
                    itemID: seasonID,
                    parameters: .detailPoster()
                ) {
                    if !urls.contains(seasonURL) {
                        urls.append(seasonURL)
                    }
                }
            }
        }

        // 4. Thumb / Backdrop fallback
        if let id = currentItem.id {
            if currentItem.imageTags?.keys.contains("Thumb") == true {
                if let thumbURL = client.itemImageURL(
                    itemID: id,
                    imageType: "Thumb",
                    parameters: .thumbnail()
                ) {
                    if !urls.contains(thumbURL) {
                        urls.append(thumbURL)
                    }
                }
            }
            if currentItem.backdropImageTags?.isEmpty == false || currentItem.imageTags?.keys.contains("Backdrop") == true {
                if let backdropURL = client.itemImageURL(
                    itemID: id,
                    imageType: "Backdrop",
                    parameters: .backdrop(maxWidth: 800, quality: 90)
                ) {
                    if !urls.contains(backdropURL) {
                        urls.append(backdropURL)
                    }
                }
            }
        }

        return urls
    }

    private func loadArtwork(for targetItem: BaseItemDto? = nil, timeoutSeconds: Double = 2.5) async -> (Data, UIImage)? {
        let urls = resolveArtworkURLs(for: targetItem)
        guard !urls.isEmpty else { return nil }

        // 1. Check SDWebImage memory or disk cache first (instant)
        for url in urls {
            let cacheKey = SDWebImageManager.shared.cacheKey(for: url) ?? url.absoluteString
            if let img = SDImageCache.shared.imageFromMemoryCache(forKey: cacheKey) ?? SDImageCache.shared.imageFromDiskCache(forKey: cacheKey) {
                if let data = img.jpegData(compressionQuality: 0.85) ?? img.pngData() {
                    AppLogger.debug("Loaded poster artwork from SDImageCache for \(title)", tag: "Player")
                    return (data, img)
                }
            }
        }

        // 2. Fetch asynchronously if not cached
        for url in urls {
            if let img = await fetchImage(for: url, timeoutSeconds: timeoutSeconds) {
                if let data = img.jpegData(compressionQuality: 0.85) ?? img.pngData() {
                    AppLogger.debug("Downloaded poster artwork for \(title)", tag: "Player")
                    return (data, img)
                }
            }
        }

        return nil
    }

    private nonisolated final class ArtworkFetchBox: @unchecked Sendable {
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

    private func fetchImage(for url: URL, timeoutSeconds: Double) async -> UIImage? {
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
                            AppLogger.debug("SDWebImage fetch failed for \(url.lastPathComponent): \(error.localizedDescription)", tag: "Player")
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

    private func startAsyncArtworkFetchIfNeeded() {
        guard loadedArtworkImage == nil else { return }
        artworkTask?.cancel()
        artworkTask = Task { @MainActor [weak self] in
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
                    AppLogger.debug("Attached delayed poster artwork to active playerItem metadata", tag: "Player")
                }
            }
        }
    }

    private func updateNowPlayingInfo(with artworkImage: UIImage) {
        #if canImport(MediaPlayer)
        var nowPlayingInfo: [String: Any] = [:]
        nowPlayingInfo[MPMediaItemPropertyTitle] = title
        if let sub = subtitle {
            nowPlayingInfo[MPMediaItemPropertyArtist] = sub
        }
        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = Double(durationTicks) / 10_000_000.0
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = Double(currentPositionTicks) / 10_000_000.0
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0

        let artwork = MPMediaItemArtwork(boundsSize: artworkImage.size) { _ in artworkImage }
        nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
        AppLogger.debug("Updated MPNowPlayingInfoCenter with title: '\(title)', artist: '\(subtitle ?? "nil")', artwork: \(Int(artworkImage.size.width))x\(Int(artworkImage.size.height))", tag: "Player")
        #endif
    }

    func cleanup() {
        guard !isCleanedUp else { return }
        isCleanedUp = true
        AppLogger.info("Cleaning up PlayerViewModel resources for '\(title)'", tag: "Player")

        periodicReportTimer?.invalidate()
        periodicReportTimer = nil

        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
            timeObserverToken = nil
        }

        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }

        statusObserver?.invalidate()
        statusObserver = nil

        muteObserver?.invalidate()
        muteObserver = nil

        artworkTask?.cancel()
        artworkTask = nil
        loadedArtworkImage = nil
        videoNaturalSize = nil

        showUpNextOverlay = false
        if let preloaded = preloadedMedia {
            (preloaded.playerItem.asset as? AVURLAsset)?.cancelLoading()
            preloadedMedia = nil
        }

        #if canImport(MediaPlayer)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        #endif

        player?.pause()
        player?.rate = 0.0

        if let currentItem = player?.currentItem {
            (currentItem.asset as? AVURLAsset)?.cancelLoading()
        }
        player?.replaceCurrentItem(with: nil)
        player = nil

        URLCache.shared.removeAllCachedResponses()
        deactivateAudioSession()

        if hasReportedStart, let client, let itemID = item.id {
            let finalTicks = currentPositionTicks
            let sessionID = playSessionID
            let sourceID = mediaSourceID
            Task.detached {
                let stopInfo = PlaybackStopInfo(
                    itemID: itemID,
                    mediaSourceID: sourceID,
                    playSessionID: sessionID,
                    positionTicks: finalTicks
                )
                _ = try? await client.reportPlaybackStopped(stopInfo)
            }
        }
    }

    private func activateAudioSession() async throws {
        if #available(iOS 27.0, *) {
            try await AVAudioSession.sharedInstance().activate()
        } else {
            try await Task.detached {
                try AVAudioSession.sharedInstance().setActive(true)
            }.value
        }
    }

    private func deactivateAudioSession() {
        Task.detached {
            do {
                if #available(iOS 27.0, *) {
                    try await AVAudioSession.sharedInstance().deactivate(options: [.notifyOthersOnDeactivation])
                } else {
                    try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
                }
            } catch {
                AppLogger.debug("Audio session deactivation info: \(error.localizedDescription)", tag: "Player")
            }
        }
    }

    // MARK: - Playback Diagnostics

    public var playbackDiagnosticSummary: String {
        var items: [String] = []
        items.append("Method: \(currentPlayMethod.rawValue)")
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
            let videoSize = videoNaturalSize ?? (presentationSize != .zero ? presentationSize : nil)
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
                                self?.videoNaturalSize = size
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

    deinit {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                cleanup()
            }
        }
    }
}
