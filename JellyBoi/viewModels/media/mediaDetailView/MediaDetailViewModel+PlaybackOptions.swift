//
//  MediaDetailViewModel+PlaybackOptions.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 9/2/26.
//

import Foundation
import JellyfinAPI
import LoggingKit

// MARK: - Playback Configuration (Video Quality / Bitrate, Audio, Subtitles, Movie Versions)

extension MediaDetailViewModel {

    struct QualityOption: Identifiable, Hashable {
        let id: String
        let label: String
        let maxBitrate: Int?
    }

    static let standardBitratePresets: [Int] = [
        120_000_000,
        80_000_000,
        60_000_000,
        40_000_000,
        20_000_000,
        15_000_000,
        10_000_000,
        8_000_000,
        6_000_000,
        4_000_000,
        3_000_000,
        2_000_000,
        1_500_000,
        1_000_000,
        720_000,
        420_000
    ]

    static let fallbackBitratePresets: [Int] = [
        20_000_000,
        10_000_000,
        8_000_000,
        6_000_000,
        4_000_000,
        3_000_000,
        2_000_000,
        1_500_000,
        1_000_000,
        720_000,
        420_000
    ]

    // MARK: - Movie Files / Media Sources

    var hasMultipleMediaSources: Bool {
        mediaSources.count > 1
    }

    var selectedMediaSource: MediaSourceInfo? {
        if let id = selectedMediaSourceID {
            return mediaSources.first(where: { $0.id == id }) ?? mediaSources.first
        }
        return mediaSources.first
    }

    var selectedMediaSourceName: String {
        guard let source = selectedMediaSource else { return "Default" }
        return mediaSourceName(for: source)
    }

    func mediaSourceName(for source: MediaSourceInfo) -> String {
        let bitText = sourceBitrateText(for: source)
        if let sName = source.name, !sName.isEmpty {
            return "\(sName)\(bitText)"
        }
        if let container = source.container, !container.isEmpty {
            return "\(container.uppercased())\(bitText)"
        }
        return "Version\(bitText)"
    }

    private func sourceBitrateText(for source: MediaSourceInfo) -> String {
        let sBitrate = (source.bitrate.flatMap { $0 > 0 ? $0 : nil })
            ?? (source.mediaStreams ?? []).first(where: { $0.type == .video })?.bitRate.flatMap { $0 > 0 ? $0 : nil }
        return sBitrate.map { " (\(formatBitrate($0)))" } ?? ""
    }

    // MARK: - Streams for Active Source

    var availableAudioStreams: [MediaStream] {
        guard let source = selectedMediaSource else { return [] }
        return (source.mediaStreams ?? []).filter { $0.type == .audio }
    }

    var availableSubtitleStreams: [MediaStream] {
        guard let source = selectedMediaSource else { return [] }
        return (source.mediaStreams ?? []).filter { $0.type == .subtitle }
    }

    var currentVideoStream: MediaStream? {
        guard let source = selectedMediaSource else { return nil }
        return (source.mediaStreams ?? []).first(where: { $0.type == .video } )
    }

    func formatBitrate(_ bps: Int) -> String {
        guard bps > 0 else { return "0 bps" }
        if bps >= 1_000_000 {
            let mbps = Double(bps) / 1_000_000.0
            if mbps >= 10 {
                return String(format: "%.0f Mbps", mbps)
            } else if mbps.truncatingRemainder(dividingBy: 1) == 0 {
                return String(format: "%.0f Mbps", mbps)
            } else {
                return String(format: "%.1f Mbps", mbps)
            }
        } else {
            let kbps = Int(round(Double(bps) / 1_000.0))
            return "\(kbps) Kbps"
        }
    }

    var currentBitrate: Int? {
        if let b = selectedMediaSource?.bitrate, b > 0 { return b }
        if let b = currentVideoStream?.bitRate, b > 0 { return b }
        return nil
    }

    // MARK: - Quality Options (Strictly Bitrate/Resolution for Active File)

    var availableQualities: [QualityOption] {
        var options: [QualityOption] = []

        let origLabel: String
        if let origBitrate = currentBitrate {
            origLabel = "Original (\(formatBitrate(origBitrate)))"
        } else {
            origLabel = "Auto (Original)"
        }
        options.append(QualityOption(
            id: "orig",
            label: origLabel,
            maxBitrate: nil
        ))

        let presetsToShow: [Int]
        if let origBitrate = currentBitrate {
            let threshold = Int(Double(origBitrate) * 0.9)
            presetsToShow = Self.standardBitratePresets.filter { $0 <= threshold }
        } else {
            presetsToShow = Self.fallbackBitratePresets
        }

        for preset in presetsToShow {
            let label = formatBitrate(preset)
            options.append(QualityOption(
                id: "bitrate-\(preset)",
                label: label,
                maxBitrate: preset
            ))
        }

        return options
    }

    var selectedQualityLabel: String {
        if let maxBitrate = selectedMaxBitrate {
            return formatBitrate(maxBitrate)
        }
        if let origBitrate = currentBitrate {
            return "Original (\(formatBitrate(origBitrate)))"
        }
        return "Auto"
    }

    func isQualitySelected(_ option: QualityOption) -> Bool {
        if let maxBitrate = option.maxBitrate {
            return selectedMaxBitrate == maxBitrate
        }
        return selectedMaxBitrate == nil
    }

    func selectQuality(_ option: QualityOption) {
        selectedMaxBitrate = option.maxBitrate
        hasCustomPlaybackOptions = true
    }

    // MARK: - Audio Stream Formatting

    func audioStreamLabel(for stream: MediaStream) -> String {
        let language = stream.localizedLanguage ?? stream.language ?? stream.displayTitle ?? "Audio"
        if let title = stream.title, !title.isEmpty {
            let lower = title.lowercased()
            let isCodecOnly = ["aac", "ac3", "eac3", "dts", "truehd", "flac", "mp3", "opus", "stereo", "5.1", "7.1"].contains { lower == $0 || lower == "\($0) 5.1" || lower == "\($0) stereo" }
            if !isCodecOnly && !lower.contains(language.lowercased()) {
                return "\(language) (\(title))"
            }
        }

        let matching = availableAudioStreams.filter { ($0.localizedLanguage ?? $0.language ?? $0.displayTitle ?? "Audio") == language }
        if matching.count > 1, let index = matching.firstIndex(where: { $0.index == stream.index }) {
            return "\(language) (\(index + 1))"
        }
        return language
    }

    var selectedAudioStreamLabel: String {
        guard let stream = availableAudioStreams.first(where: { $0.index == selectedAudioStreamIndex }) else {
            return "Default Audio"
        }
        return audioStreamLabel(for: stream)
    }

    // MARK: - Subtitle Stream Formatting

    func subtitleStreamLabel(for stream: MediaStream) -> String {
        let language = stream.localizedLanguage ?? stream.language ?? stream.displayTitle ?? "Subtitle"
        var suffixes: [String] = []
        if stream.isHearingImpaired == true {
            suffixes.append("SDH")
        } else if stream.isForced == true {
            suffixes.append("Forced")
        }

        if !ApplePlayableSubtitle.isCompatible(stream) {
            suffixes.append("Transcodes")
        }

        if let title = stream.title, !title.isEmpty {
            let lower = title.lowercased()
            let isFormatOnly = ["srt", "ass", "subrip", "vtt", "pgs", "sub"].contains { lower == $0 }
            if !isFormatOnly && !suffixes.contains(where: { lower.contains($0.lowercased()) }) && !lower.contains(language.lowercased()) {
                suffixes.append(title)
            }
        }

        if !suffixes.isEmpty {
            return "\(language) (\(suffixes.joined(separator: ", ")))"
        }

        let matching = availableSubtitleStreams.filter { ($0.localizedLanguage ?? $0.language ?? $0.displayTitle ?? "Subtitle") == language }
        if matching.count > 1, let index = matching.firstIndex(where: { $0.index == stream.index }) {
            return "\(language) (\(index + 1))"
        }
        return language
    }

    var selectedSubtitleStreamLabel: String {
        if selectedSubtitleStreamIndex == nil || selectedSubtitleStreamIndex == -1 {
            return "Off"
        }
        guard let stream = availableSubtitleStreams.first(where: { $0.index == selectedSubtitleStreamIndex }) else {
            return "Off"
        }
        return subtitleStreamLabel(for: stream)
    }

    // MARK: - Native Playback DTO Bundle

    var defaultPlaybackInfo: PlaybackInfoDto {
        PlaybackInfoDto(userID: serverViewModel?.currentUser?.id)
    }

    var currentPlaybackInfo: PlaybackInfoDto {
        guard hasCustomPlaybackOptions else {
            return defaultPlaybackInfo
        }
        return PlaybackInfoDto(
            audioStreamIndex: selectedAudioStreamIndex,
            maxStreamingBitrate: selectedMaxBitrate,
            mediaSourceID: selectedMediaSourceID,
            subtitleStreamIndex: (selectedSubtitleStreamIndex == nil || selectedSubtitleStreamIndex == -1) ? nil : selectedSubtitleStreamIndex,
            userID: serverViewModel?.currentUser?.id
        )
    }

    // MARK: - Playback Options Loading (ID-Only)

    func loadPlaybackOptions(itemID: String, client: JellyfinClient? = nil, userID: String? = nil) async {
        let activeClient = client ?? self.client ?? serverViewModel?.client ?? ServerViewModel.shared.client
        let activeUserID = userID ?? serverViewModel?.currentUser?.id ?? ServerViewModel.shared.currentUser?.id
        if mediaSources.isEmpty {
            isLoadingPlaybackOptions = true
        }

        guard let activeClient else {
            isLoadingPlaybackOptions = false
            return
        }

        do {
            let response = try await activeClient.fetchPlaybackInfo(itemID: itemID, userID: activeUserID)
            if let sources = response.mediaSources, !sources.isEmpty {
                self.mediaSources = sources
                configureInitialStreamSelection()
            }
        } catch {
            AppLogger.warning("Failed to fetch playback info for \(itemID): \(error.localizedDescription)")
        }

        isLoadingPlaybackOptions = false
    }

    func loadPlaybackOptions(for item: BaseItemDto, client: JellyfinClient? = nil, userID: String? = nil) async {
        if let itemSources = item.mediaSources, !itemSources.isEmpty {
            self.mediaSources = itemSources
            configureInitialStreamSelection()
        }

        guard let itemID = item.id else { return }
        await loadPlaybackOptions(itemID: itemID, client: client, userID: userID)
    }

    // MARK: - Selection Actions

    func configureInitialStreamSelection() {
        if selectedMediaSourceID == nil || !mediaSources.contains(where: { $0.id == selectedMediaSourceID }) {
            selectedMediaSourceID = mediaSources.first?.id
        }

        guard let source = selectedMediaSource else { return }
        applyDefaultStreamSelection(from: source, preserveExisting: true)
    }

    func selectMediaSource(_ sourceID: String?) {
        guard selectedMediaSourceID != sourceID else { return }
        selectedMediaSourceID = sourceID
        selectedMaxBitrate = nil
        hasCustomPlaybackOptions = true
        guard let source = selectedMediaSource else { return }
        applyDefaultStreamSelection(from: source, preserveExisting: false)
    }

    func selectAudioStream(index: Int?) {
        selectedAudioStreamIndex = index
        hasCustomPlaybackOptions = true
    }

    func selectSubtitleStream(index: Int?) {
        selectedSubtitleStreamIndex = index
        hasCustomPlaybackOptions = true
    }

    func resetToDefaults() {
        hasCustomPlaybackOptions = false
        selectedMaxBitrate = nil
        selectedMediaSourceID = mediaSources.first?.id
        guard let source = selectedMediaSource else {
            selectedAudioStreamIndex = nil
            selectedSubtitleStreamIndex = -1
            return
        }
        applyDefaultStreamSelection(from: source, preserveExisting: false)
    }

    private func applyDefaultStreamSelection(from source: MediaSourceInfo, preserveExisting: Bool) {
        let audios = (source.mediaStreams ?? []).filter { $0.type == .audio }
        if !preserveExisting || selectedAudioStreamIndex == nil || !audios.contains(where: { $0.index == selectedAudioStreamIndex }) {
            selectedAudioStreamIndex = source.defaultAudioStreamIndex
                ?? audios.first(where: { $0.isDefault == true })?.index
                ?? audios.first?.index
        }

        let subs = (source.mediaStreams ?? []).filter { $0.type == .subtitle }
        if !preserveExisting || selectedSubtitleStreamIndex == nil {
            if let defSub = source.defaultSubtitleStreamIndex,
               let subStream = subs.first(where: { $0.index == defSub }),
               ApplePlayableSubtitle.isCompatible(subStream) {
                // Auto-select default subtitle only when natively compatible with AVPlayer
                selectedSubtitleStreamIndex = defSub
            } else {
                selectedSubtitleStreamIndex = -1
            }
        }
    }
}
