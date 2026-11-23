//
//  OptionsSheet.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 8/23/26.
//

import SwiftUI
import UIKit
import BaseColors
import JellyfinAPI

extension MediaDetailView {

    var optionsSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            if detailVM.isLoadingPlaybackOptions {
                optionsSkeleton
            } else {
                // Dropdown 1: Movie Version (shown when multiple movie files exist)
                if detailVM.hasMultipleMediaSources {
                    versionDropdown
                        .transition(.opacity)
                }

                // Dropdown 2: Video Quality / Bitrate
                qualityDropdown
                    .transition(.opacity)

                // Dropdown 3: Audio Track
                audioDropdown
                    .transition(.opacity)

                // Dropdown 4: Subtitles
                subtitlesDropdown
                    .transition(.opacity)

                // Reset Button
                resetButton
                    .transition(.opacity)
            }
        }
        .animation(.skeleton, value: detailVM.isLoadingPlaybackOptions)
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { newHeight in
            withAnimation(.easeInOut(duration: 0.25)) {
                optionsSheetHeight = newHeight
            }
        }
        .task(id: detailVM.playableItemID) {
            let itemID = detailVM.playableItemID
            guard !itemID.isEmpty else { return }
            await detailVM.loadPlaybackOptions(
                itemID: itemID,
                client: serverViewModel.client,
                userID: serverViewModel.currentUser?.id
            )
        }
    }

    // MARK: - Skeleton View

    private var optionsSkeleton: some View {
        VStack(alignment: .leading, spacing: 18) {
            if detailVM.hasMultipleMediaSources {
                dropdownSkeletonRow(label: "Version", icon: "film.stack", value: "Default Version")
            }
            dropdownSkeletonRow(label: "Quality", icon: "film", value: "Auto (1080p)")
            dropdownSkeletonRow(label: "Audio", icon: "speaker.wave.2", value: "English (Default)")
            dropdownSkeletonRow(label: "Subtitles", icon: "captions.bubble", value: "None")
        }
        .skeleton()
        .transition(.opacity)
    }

    private func dropdownSkeletonRow(label: String, icon: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(.footnote, design: .rounded, weight: .semibold))
                .foregroundStyle(Color.mainOpp.opacity(0.55))
                .padding(.horizontal, 4)

            dropdownLabel(icon: icon, value: value)
        }
    }

    // MARK: - Version Dropdown

    private var versionDropdown: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Version")
                .font(.system(.footnote, design: .rounded, weight: .semibold))
                .foregroundStyle(Color.mainOpp.opacity(0.55))
                .padding(.horizontal, 4)

            Menu {
                ForEach(detailVM.mediaSources) { source in
                    let isSelected = (source.id == detailVM.selectedMediaSourceID)
                    let label = detailVM.mediaSourceName(for: source)
                    Button {
                        detailVM.selectMediaSource(source.id)
                    } label: {
                        if isSelected {
                            checkedMenuLabel(label)
                        } else {
                            Text(label)
                        }
                    }
                }
            } label: {
                dropdownLabel(
                    icon: "film.stack",
                    value: detailVM.selectedMediaSourceName
                )
            }
            .menuStyle(.button)
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
                ForEach(detailVM.availableQualities) { option in
                    Button {
                        detailVM.selectQuality(option)
                    } label: {
                        if isQualitySelected(option) {
                            checkedMenuLabel(option.label)
                        } else {
                            Text(option.label)
                        }
                    }
                }
            } label: {
                dropdownLabel(
                    icon: "film",
                    value: detailVM.selectedQualityLabel
                )
            }
            .menuStyle(.button)
        }
    }

    private func isQualitySelected(_ option: MediaDetailViewModel.QualityOption) -> Bool {
        detailVM.isQualitySelected(option)
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
                        checkedMenuLabel("Default Audio")
                    }
                } else {
                    ForEach(detailVM.availableAudioStreams, id: \.index) { stream in
                        let isSelected = (stream.index == detailVM.selectedAudioStreamIndex)
                        let label = detailVM.audioStreamLabel(for: stream)
                        Button {
                            detailVM.selectAudioStream(index: stream.index)
                        } label: {
                            if isSelected {
                                checkedMenuLabel(label)
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
                let isOff = (detailVM.selectedSubtitleStreamIndex == nil || detailVM.selectedSubtitleStreamIndex == -1)
                Button {
                    detailVM.selectSubtitleStream(index: -1)
                } label: {
                    if isOff {
                        checkedMenuLabel("Off")
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
                            checkedMenuLabel(label)
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

    // MARK: - Helper Views

    private func checkedMenuLabel(_ title: String) -> some View {
        Label(title, systemImage: "checkmark")
    }

    private func dropdownLabel(icon: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.appAccent)
                .frame(width: 20)

            Text(value)
                .font(.system(size: 15, weight: .regular, design: .rounded))
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
        .glassEffect(.regular.tint(Color.appAccent).interactive(), in: Capsule())
        .foregroundStyle(.white)
        .buttonStyle(.plain)
        .padding(.top, 4)
    }
}
