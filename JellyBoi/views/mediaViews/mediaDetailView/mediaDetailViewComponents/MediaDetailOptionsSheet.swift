//
//  MediaDetailOptionsSheet.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 8/23/26.
//

import SwiftUI
import BaseColors
import JellyfinAPI

extension MediaDetailView {

    var optionsSheet: some View {
        
            VStack(alignment: .leading, spacing: 18) {
                if detailVM.isLoadingPlaybackOptions {
                    HStack(spacing: 12) {
                        ProgressView()
                            .tint(Color.mainOpp)
                        Text("Loading media streams…")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(Color.mainOpp.opacity(0.7))
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 36)
                } else {
                    // Dropdown 1: Video Quality / Resolution
                    qualityDropdown

                    // Dropdown 2: Audio Track
                    audioDropdown

                    // Dropdown 3: Subtitles
                    subtitlesDropdown

                    // Reset Button
                    resetButton
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height + proxy.safeAreaInsets.bottom
            } action: { newHeight in
                withAnimation(.easeInOut(duration: 0.25)) {
                    optionsSheetHeight = newHeight
                }
            }
        
        .task(id: playableItem.id) {
            let target = playableItem
            await detailVM.loadPlaybackOptions(
                for: target,
                client: serverViewModel.client,
                userID: serverViewModel.currentUser?.id
            )
        }
    }

    // MARK: - Quality Dropdown

    private var qualityDropdown: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Quality")
                .font(.system(.footnote, design: .rounded, weight: .semibold))
                .foregroundStyle(Color.mainOpp.opacity(0.55))
                .padding(.horizontal, 4)

            Menu {
                ForEach(detailVM.availableResolutions) { option in
                    Button {
                        detailVM.selectResolution(option)
                    } label: {
                        if isResolutionSelected(option) {
                            Label(option.label, systemImage: "checkmark")
                        } else {
                            Text(option.label)
                        }
                    }
                }
            } label: {
                dropdownLabel(
                    icon: "film",
                    value: detailVM.selectedResolutionLabel
                )
            }
            .menuStyle(.button)
        }
    }

    private func isResolutionSelected(_ option: MediaDetailViewModel.ResolutionOption) -> Bool {
        if let maxHeight = option.maxHeight {
            return detailVM.selectedMaxHeight == maxHeight
        }
        if detailVM.selectedMaxHeight != nil {
            return false
        }
        if let sourceID = option.mediaSourceID {
            return detailVM.selectedMediaSourceID == sourceID
        }
        return true
    }

    // MARK: - Audio Dropdown

    private var audioDropdown: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Audio")
                .font(.system(.footnote, design: .rounded, weight: .semibold))
                .foregroundStyle(Color.mainOpp.opacity(0.55))
                .padding(.horizontal, 4)

            Menu {
                if detailVM.availableAudioStreams.isEmpty {
                    Button {
                        // Default
                    } label: {
                        Label("Default Audio", systemImage: "checkmark")
                    }
                } else {
                    ForEach(detailVM.availableAudioStreams, id: \.index) { stream in
                        let isSelected = (stream.index == detailVM.selectedAudioStreamIndex)
                        let label = detailVM.audioStreamLabel(for: stream)
                        Button {
                            detailVM.selectAudioStream(index: stream.index)
                        } label: {
                            if isSelected {
                                Label(label, systemImage: "checkmark")
                            } else {
                                Text(label)
                            }
                        }
                    }
                }
            } label: {
                dropdownLabel(
                    icon: "speaker.wave.2",
                    value: detailVM.selectedAudioStreamLabel
                )
            }
            .menuStyle(.button)
        }
    }

    // MARK: - Subtitles Dropdown

    private var subtitlesDropdown: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Subtitles")
                .font(.system(.footnote, design: .rounded, weight: .semibold))
                .foregroundStyle(Color.mainOpp.opacity(0.55))
                .padding(.horizontal, 4)

            Menu {
                // "Off" option
                let isOff = (detailVM.selectedSubtitleStreamIndex == nil || detailVM.selectedSubtitleStreamIndex == -1)
                Button {
                    detailVM.selectSubtitleStream(index: -1)
                } label: {
                    if isOff {
                        Label("Off", systemImage: "checkmark")
                    } else {
                        Text("Off")
                    }
                }

                ForEach(detailVM.availableSubtitleStreams, id: \.index) { stream in
                    let isSelected = (stream.index == detailVM.selectedSubtitleStreamIndex)
                    let label = detailVM.subtitleStreamLabel(for: stream)
                    Button {
                        detailVM.selectSubtitleStream(index: stream.index)
                    } label: {
                        if isSelected {
                            Label(label, systemImage: "checkmark")
                        } else {
                            Text(label)
                        }
                    }
                }
            } label: {
                dropdownLabel(
                    icon: "captions.bubble",
                    value: detailVM.selectedSubtitleStreamLabel
                )
            }
            .menuStyle(.button)
        }
    }

    // MARK: - Dropdown Label Component

    private func dropdownLabel(icon: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.mainOpp.opacity(0.75))
                .frame(width: 22)

            Text(value)
                .font(.system(.body, design: .rounded, weight: .medium))
                .foregroundStyle(Color.mainOpp)
                .lineLimit(1)

            Spacer()

            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.mainOpp.opacity(0.35))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .frame(maxWidth: .infinity)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Reset Button

    private var resetButton: some View {
        Button {
            withAnimation {
                detailVM.resetToDefaults()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 13, weight: .semibold))
                Text("Reset to Default")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
        .glassEffect(.regular.tint(.accent).interactive(), in: Capsule())
        .foregroundStyle(.white)
        .buttonStyle(.plain)
        .padding(.top, 4)
    }
}
