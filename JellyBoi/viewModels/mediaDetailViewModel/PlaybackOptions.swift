//
//  PlaybackOptions.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 9/2/26.
//

import Foundation
import JellyfinAPI
import LoggingKit

// MARK: - Playback Configuration (Video Quality / Bitrate, Audio, Subtitles)

extension MediaDetailViewModel {

    struct QualityOption: Identifiable, Hashable {
        let id: String
        let label: String
        let mediaSourceID: String?
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

    var selectedMediaSource: MediaSourceInfo? {
        if let id = selectedMediaSourceID {
            return mediaSources.first(where: { $0.id == id }) ?? mediaSources.first
        }
        return mediaSources.first
    }

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
        return (source.mediaStreams ?? []).first(where: { $0.type == .video })
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

    var availableQualities: [QualityOption] {
        var options: [QualityOption] = []

        if mediaSources.count > 1 {
            for source in mediaSources {
                let sBitrate = (source.bitrate.flatMap { $0 > 0 ? $0 : nil })
                    ?? (source.mediaStreams ?? []).first(where: { $0.type == .video })?.bitRate.flatMap { $0 > 0 ? $0 : nil }
                let bitText = sBitrate.map { " (\(formatBitrate($0)))" } ?? ""
                let name: String
                if let sName = source.name, !sName.isEmpty {
                    name = "\(sName)\(bitText)"
                } else if sBitrate != nil {
                    name = "Original\(bitText)"
                } else {
                    name = "Version"
                }
                options.append(QualityOption(
                    id: source.id ?? UUID().uuidString,
                    label: name,
                    mediaSourceID: source.id,
                    maxBitrate: nil
                ))
            }
        } else {
            let origLabel: String
            if let origBitrate = currentBitrate {
                origLabel = "Original (\(formatBitrate(origBitrate)))"
            } else {
                origLabel = "Auto (Original)"
            }
            options.append(QualityOption(
                id: "orig",
                label: origLabel,
                mediaSourceID: selectedMediaSourceID,
                maxBitrate: nil
            ))
        }

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
                mediaSourceID: selectedMediaSourceID,
                maxBitrate: preset
            ))
        }

        return options
    }

    var selectedQualityLabel: String {
        if let maxBitrate = selectedMaxBitrate {
            return formatBitrate(maxBitrate)
        }
        if mediaSources.count > 1, let source = selectedMediaSource {
            let sBitrate = (source.bitrate.flatMap { $0 > 0 ? $0 : nil })
                ?? currentVideoStream?.bitRate.flatMap { $0 > 0 ? $0 : nil }
            let bitText = sBitrate.map { " (\(formatBitrate($0)))" } ?? ""
            if let sName = source.name, !sName.isEmpty {
                return "\(sName)\(bitText)"
            }
            return sBitrate.map { "Original (\(formatBitrate($0)))" } ?? "Original"
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
        if selectedMaxBitrate != nil {
            return false
        }
        if let sourceID = option.mediaSourceID {
            return selectedMediaSourceID == sourceID
        }
        return true
    }

    func selectQuality(_ option: QualityOption) {
        if let sourceID = option.mediaSourceID {
            selectMediaSource(sourceID)
        }
        selectedMaxBitrate = option.maxBitrate
    }

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

    func subtitleStreamLabel(for stream: MediaStream) -> String {
        let language = stream.localizedLanguage ?? stream.language ?? stream.displayTitle ?? "Subtitle"
        var suffixes: [String] = []
        if stream.isHearingImpaired == true {
            suffixes.append("SDH")
        } else if stream.isForced == true {
            suffixes.append("Forced")
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

    func loadPlaybackOptions(for item: BaseItemDto, client: JellyfinClient?, userID: String?) async {
        if let itemSources = item.mediaSources, !itemSources.isEmpty {
            self.mediaSources = itemSources
            configureInitialStreamSelection()
        }

        guard let client, let itemID = item.id else { return }

        if mediaSources.isEmpty {
            isLoadingPlaybackOptions = true
        }

        do {
            let response = try await client.fetchPlaybackInfo(itemID: itemID, userID: userID)
            if let sources = response.mediaSources, !sources.isEmpty {
                self.mediaSources = sources
                configureInitialStreamSelection()
            }
        } catch {
            AppLogger.warning("Failed to fetch playback info: \(error.localizedDescription)")
        }

        isLoadingPlaybackOptions = false
    }

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
        guard let source = selectedMediaSource else { return }
        applyDefaultStreamSelection(from: source, preserveExisting: false)
    }

    func selectAudioStream(index: Int?) {
        selectedAudioStreamIndex = index
    }

    func selectSubtitleStream(index: Int?) {
        selectedSubtitleStreamIndex = index
    }

    func resetToDefaults() {
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
            if let defSub = source.defaultSubtitleStreamIndex, subs.contains(where: { $0.index == defSub }) {
                selectedSubtitleStreamIndex = defSub
            } else {
                selectedSubtitleStreamIndex = -1
            }
        }
    }
}
