//
//  JellyfinDeviceProfile.swift
//  JellyBoi
//
//  Step 2: Stream Resolution (Device Capabilities)
//  Advertises Apple-native player playback capabilities to Jellyfin
//  so the server can decide between Direct Play, Direct Stream, and HLS Transcoding.
//

import JellyfinAPI

/// Device profiles advertised to Jellyfin when negotiating playback (Step 2: Stream Resolution).
///
/// This is pure data: it describes what AVPlayer can open natively, which is what lets the server
/// decide between direct play, HLS remuxing, and transcoding.
nonisolated enum JellyfinDeviceProfile {

    /// Native Apple playback: MP4/MOV containers with H.264/HEVC video, plus sidecar subtitles.
    static var appleNative: DeviceProfile {
        DeviceProfile(
            directPlayProfiles: [
                DirectPlayProfile(
                    audioCodec: "aac,mp3,ac3,eac3,alac,flac",
                    container: ApplePlayableContainer.jellyfinContainerList,
                    type: .video,
                    videoCodec: "h264,hevc"
                ),
                DirectPlayProfile(
                    audioCodec: "aac,mp3,alac,flac,wav",
                    container: "mp3,m4a,aac,flac,wav",
                    type: .audio
                )
            ],
            maxStaticBitrate: 140_000_000,
            maxStreamingBitrate: 140_000_000,
            name: "Apple Native Player",
            subtitleProfiles: [
                SubtitleProfile(format: "vtt", method: .hls),
                SubtitleProfile(format: "webvtt", method: .hls),
                SubtitleProfile(format: "subrip", method: .hls),
                SubtitleProfile(format: "srt", method: .hls),
                SubtitleProfile(format: "ass", method: .encode),
                SubtitleProfile(format: "ssa", method: .encode),
                SubtitleProfile(format: "pgs", method: .encode),
                SubtitleProfile(format: "pgssub", method: .encode),
                SubtitleProfile(format: "sub", method: .encode),
                SubtitleProfile(format: "dvd_subtitle", method: .encode)
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
                    segmentLength: 6,
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
                    segmentLength: 6,
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
                    segmentLength: 6,
                    transcodeSeekInfo: .auto,
                    type: .audio
                )
            ]
        )
    }
}
