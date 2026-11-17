<div align="center">

# JellyBoi

**A sleek, high-performance, native Jellyfin client crafted in SwiftUI for Apple devices.**

[![Platform](https://img.shields.io/badge/Platform-iOS%20%7C%20iPadOS%20%7C%20macOS%20%7C%20tvOS%20%7C%20visionOS-000000?style=for-the-badge&logo=apple&logoColor=white)](https://developer.apple.com/)
[![Swift](https://img.shields.io/badge/Swift-5.10%20%2F%206.0-F05138?style=for-the-badge&logo=swift&logoColor=white)](https://swift.org)
[![SwiftUI](https://img.shields.io/badge/SwiftUI-Liquid%20Glass-007AFF?style=for-the-badge&logo=swift&logoColor=white)](https://developer.apple.com/swiftui/)
[![Jellyfin](https://img.shields.io/badge/Jellyfin-Client-00A4DC?style=for-the-badge&logo=jellyfin&logoColor=white)](https://jellyfin.org)
[![License: Proprietary](https://img.shields.io/badge/License-Proprietary%20%2F%20All%20Rights%20Reserved-red.svg?style=for-the-badge)](#license--copyright)

</div>

---

## Visual Showcase & Media Pipeline

### Browse & Experience
| Home & Discovery | Media Library | Detailed Media View |
| :---: | :---: | :---: |
| <img src="docs/assets/screenshots/home-view.png" width="240" alt="Home & Discovery"/> | <img src="docs/assets/screenshots/library-view.png" width="240" alt="Media Library"/> | <img src="docs/assets/screenshots/media-detail-view.png" width="240" alt="Media Detail View"/> |

---

### Player, Search & Deep Metadata
| Native Video Player | Ranked Search | Cast & Crew Credits |
| :---: | :---: | :---: |
| <img src="docs/assets/screenshots/player-view.png" width="240" alt="Native Video Player"/> | <img src="docs/assets/screenshots/search-view.png" width="240" alt="Ranked Search"/> | <img src="docs/assets/screenshots/cast-crew-view.png" width="240" alt="Cast & Crew Credits"/> |

---

## Overview

**JellyBoi** is a premium, native Apple client engineered specifically for [Jellyfin](https://jellyfin.org) personal media servers. Designed from the ground up utilizing modern **SwiftUI**, Swift Concurrency, and Apple's AVFoundation media pipelines, JellyBoi delivers a deeply integrated streaming and offline experience across iOS, iPadOS, macOS, tvOS, and visionOS.

Equipped with an on-device FFmpeg remuxing engine, background URLSession download pipeline, ActivityKit Live Activities, and a weighted multi-attribute search ranker, JellyBoi provides a blazing fast and visually stunning media experience.

---

## Key Features

### Native Playback Engine
- **Hardware-Accelerated Streaming**: Built on AVFoundation and AVKit with direct streaming and server-driven adaptive HLS fallback.
- **Smart Orientation Management**: Smooth orientation handling and aspect-ratio preservation across all device sizes.
- **Real-Time Playback Synchronization**: Live watch-percentage, resume timestamps, and playback state reporting synced back to the Jellyfin server.
- **On-Screen Audio & Subtitle Control**: Switch audio streams and embedded/external subtitle tracks dynamically with zero playback stall.
- **Diagnostics Overlay**: Real-time bitrates, audio channels, dropped frames, and stream container specs for power users.

### Offline Media Pipeline & On-Device Remuxing
- **Resilient Background Transfers**: Native `URLSessionDownloadTask` background management with auto-resume, battery-conscious queuing, and network handoff.
- **On-Device FFmpeg Remuxing (`LocalMediaRemuxer`)**: Fast, lossless container remuxing (MKV/WebM to MP4) using low-level `Libavformat` and `Libavcodec` on background utility threads to ensure native Apple hardware decoder compatibility.
- **Live Activities & Dynamic Island**: Real-time download progress tracking, percentage meters, and thumbnail previews via ActivityKit.
- **Offline Storage Management**: Dedicated downloads vault with offline playback, storage cleanup, and grouped media browsing.

### Ranked Media Search
- **MediaSearchRanker**: Custom multi-factor scoring engine evaluating title match precision, release recency, popularity, and media kind weighting.
- **Instant Diacritic-Insensitive Search**: Normalized Unicode search across movies, TV series, episodes, collections, and people.
- **Dynamic Filter Pills**: Instant narrowing by media type, genre, played status, and favorite flags.

### Refined Apple-First UI
- **Immersive Hero Carousels**: Dynamic backdrop scaling, blur transitions, and responsive parallax headers.
- **Rich Cast & Crew Views**: Detailed cast profiles, character roles, person bios, and filmography cross-linking.
- **Continuous Watching & Next Up**: Instant single-tap resumption for interrupted cinema and television queues.
- **Liquid Glass Aesthetic**: Glassmorphism styling, native Apple materials, and dynamic theme palette support.

### Security & Multi-Server Management
- **Quick Connect**: Seamless pairing with home servers using one-time verification codes.
- **Keychain Token Security**: Session credentials and auth tokens securely sealed inside the Apple Keychain via `KeychainStore`.
- **Automatic Reconnection**: Resilient websocket and REST session restoration after network switches.

---

## System Architecture

```mermaid
graph TD
    subgraph Presentation ["Presentation Layer (SwiftUI + Liquid Glass)"]
        HOME["HomeView & Hero Carousels"]
        LIB["Library & Collection Views"]
        DETAIL["MediaDetailView & Cast Crew"]
        PLAYER["PlayerView & AVKit Controls"]
        SEARCH["Search & Ranked Results"]
    end

    subgraph State ["State & Observation Layer"]
        HVM["HomeViewModel"]
        MDVM["MediaDetailViewModel"]
        SVM["SearchViewModel"]
        PVM["PlayerViewModel"]
        DM["DownloadsManager"]
    end

    subgraph Processing ["Core Media & Background Pipelines"]
        PSR["PlaybackStreamResolver"]
        MSR["MediaSearchRanker"]
        LMR["LocalMediaRemuxer (Libavformat / FFmpeg)"]
        AC["DownloadActivityCoordinator (ActivityKit)"]
    end

    subgraph Hardware ["Apple Media & System Frameworks"]
        AVP["AVFoundation / AVPlayer Engine"]
        BG["URLSession Background Transfers"]
        KC["KeychainStore (Security Framework)"]
    end

    subgraph Remote ["Backend & Networking"]
        JF["Jellyfin REST API & Realtime WebSockets"]
    end

    HOME --> HVM
    LIB --> HVM
    DETAIL --> MDVM
    SEARCH --> SVM
    PLAYER --> PVM

    HVM --> JF
    MDVM --> JF
    SVM --> MSR
    MSR --> JF

    PVM --> PSR
    PSR --> AVP
    PSR --> JF

    DM --> BG
    DM --> LMR
    DM --> AC
    BG --> JF

    PVM --> KC
    HVM --> KC
```

---

## Tech Stack & Dependencies

| Component | Framework / Library | Role |
| :--- | :--- | :--- |
| **Presentation** | `SwiftUI`, `BaseColors`, `Liquid Glass` | Modern declarative UI, materials, and themes |
| **Animation & Headers** | `ScalingHeaderScrollView`, `MarqueeText`, `SkeletonUI` | Fluid parallax scrolling and animated placeholders |
| **State & Concurrency** | Swift Observation (`@Observable`, `@State`), Swift Concurrency | Modern, Combine-free reactive state and async tasks |
| **Media Playback** | `AVKit`, `AVFoundation` | Native hardware-accelerated video decoding |
| **Remuxing Pipeline** | `FFmpegKit`, `Libavformat`, `Libavcodec`, `Libavutil` | On-device container remuxing for Apple compatibility |
| **Networking & API** | `JellyfinAPI`, `Get`, `URLSession` Background Tasks | Type-safe REST communication and background downloads |
| **Live Activities** | `ActivityKit` | Dynamic Island and Lock Screen download progress |
| **Image Pipeline** | `SDWebImageSwiftUI`, `SDWebImage` | Asynchronous image decoding, memory caching, and disk caching |
| **Security** | `KeychainStore` (`Security.framework`) | Encrypted credential and token persistence |
| **Logging & Overlay** | `LoggingKit` (`AppLogger`), `StatusOverlayKit` | Unified structured diagnostics and HUD indicators |

---

## Requirements

- **iOS / iPadOS**: 18.0 or later
- **macOS**: 15.0 or later *(Designed for iPad / Mac Catalyst)*
- **tvOS**: 18.0 or later
- **visionOS**: 1.0 or later
- **Xcode**: 16.0 or later
- **Jellyfin Server**: v10.8.0+ (v10.9+ recommended)

---

## Getting Started

### 1. Clone the Repository

```bash
git clone https://github.com/GarrettButchko/jellyboi.git
cd jellyboi
```

### 2. Open in Xcode

```bash
open JellyBoi.xcodeproj
```

Xcode will automatically resolve all Swift Package dependencies.

### 3. Build & Run

1. Select your target device (e.g., iPhone 16 Pro Simulator or physical iOS device).
2. Choose the **JellyBoi** scheme.
3. Press `Cmd + R` to compile and launch.
4. Input your Jellyfin server address and sign in or use Quick Connect.

---

## GitHub Repository Metadata

Use these values when configuring your GitHub repository settings:

### Description
> Sleek, high-performance native Jellyfin client crafted in SwiftUI for iOS, iPadOS, macOS, tvOS, and visionOS with on-device remuxing, offline downloads, and Live Activities.

### Topics / Tags
```text
jellyfin, jellyfin-client, swift, swiftui, ios, ipados, macos, tvos, visionos, avplayer, avfoundation, ffmpeg, ffmpegkit, remuxing, offline-downloads, live-activities, dynamic-island, media-player, video-streaming, entertainment
```

---

## License & Copyright

**Copyright (c) 2024-present Garrett Butchko. All rights reserved.**

The source code, design assets, and documentation contained in this repository are proprietary and confidential. This repository is source-available solely for portfolio viewing, learning, and architectural evaluation purposes.

No permission is granted to copy, modify, distribute, sublicense, or sell copies of the software, or to launch commercial services derived from this codebase, without explicit prior written authorization from the copyright holder.

For licensing inquiries or commercial use permissions, please contact Garrett Butchko.
