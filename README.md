# 🪼 JellyBoi

<div align="center">

![Platform](https://img.shields.io/badge/Platform-iOS%20%7C%20iPadOS%20%7C%20macOS%20%7C%20tvOS%20%7C%20visionOS-blue?style=for-the-badge&logo=apple)
![Swift](https://img.shields.io/badge/Swift-5.0%20%2F%206-F05138?style=for-the-badge&logo=swift&logoColor=white)
![SwiftUI](https://img.shields.io/badge/SwiftUI-4.0+-007AFF?style=for-the-badge&logo=swift&logoColor=white)
![Jellyfin](https://img.shields.io/badge/Jellyfin-Client-00A4DC?style=for-the-badge&logo=jellyfin&logoColor=white)
![License: GPL v3](https://img.shields.io/badge/License-GPLv3%20with%20App%20Store%20Exception-blue.svg?style=for-the-badge&logo=gnu)

**A sleek, modern, native Jellyfin client crafted in SwiftUI for Apple devices.**

[Features](#-features) • [Screenshots & UI](#-architecture--design) • [Tech Stack](#-tech-stack--dependencies) • [Getting Started](#-getting-started) • [Tags & Topics](#-repository-tags--topics)

</div>

---

## 📖 Overview

**JellyBoi** is an open-source, high-performance media client designed specifically for [Jellyfin](https://jellyfin.org) media servers. Built from the ground up using modern **SwiftUI** and Swift Concurrency, JellyBoi brings a fluid, responsive, and native streaming and offline playback experience to iOS, iPadOS, macOS, tvOS, and visionOS.

Whether browsing your 4K movie library, catching up on Next Up episodes, or preparing offline downloads with on-device remuxing, JellyBoi delivers a refined Apple-first aesthetic.

---

## ✨ Features

- 🏠 **Dynamic Home Experience**
  - **Hero Backdrops & Carousels**: Immersive, fluid previews for featured and trending titles.
  - **Continue Watching & Next Up**: Instant resumption of interrupted movies and episodic television.
  - **Recently Added**: Real-time carousels of newly synced movies, shows, and music.

- 🎬 **Native Media Playback**
  - **AVKit Player Engine**: Hardware-accelerated playback supporting AVPlayer.
  - **Orientation Management**: Seamless orientation locking and rotation handling.
  - **Playback Progress Sync**: Live status and watch percentage reporting back to your Jellyfin server.
  - **In-Player Controls**: Fast seeking, audio & subtitle track switching, and debug diagnostics overlay.

- 📥 **Offline Downloads & On-Device Remuxing**
  - **Background Downloads**: Resilient background downloading using native `URLSession` background sessions with automatic retry logic.
  - **Local Remuxing with FFmpeg**: On-device remuxing via `FFmpegKit` for formats requiring local container adjustments for Apple native playback.
  - **Download Management**: Dedicated downloads sheet with live progress tracking, storage management, and offline playback support.

- 🔍 **Ranked Media Search**
  - **Instant Search**: Lightning-fast search across titles, series, artists, and people.
  - **MediaSearchRanker**: Weighted ranking algorithm prioritizing exact matches, recent media, and popularity.
  - **Dynamic Filters**: Filter results by media type, genre, and collections.

- 🏷️ **Comprehensive Media Details**
  - **Full Metadata**: Cast & crew credits, episode guides, collection sets, similar recommendations, and metadata tags with flow layout.
  - **Quick Actions**: Mark favorite, toggle played/unplayed, download for offline, and quick stream.

- 🔐 **Secure Authentication & Multi-Server**
  - **Quick Connect**: Pair effortlessly with your Jellyfin server via Quick Connect code.
  - **Credential Security**: Secure credential and token management stored inside the Apple Keychain (`KeychainStore`).
  - **Automatic Session Restoration**: Instant re-authentication on launch.

---

## 🛠 Tech Stack & Dependencies

JellyBoi leverages modern Apple frameworks and select open-source libraries:

| Layer | Technologies |
|---|---|
| **UI & Presentation** | SwiftUI, Liquid Glass/Materials, BaseColors, ScalingHeaderScrollView, MarqueeText, SkeletonUI |
| **State & Architecture** | Swift Concurrency (`async`/`await`, `Task`), Swift Observation (`@Observable`, `@Bindable`, `@Environment`) |
| **Media & Audio** | AVFoundation, AVKit, FFmpegKit (on-device remuxing) |
| **Networking & API** | JellyfinAPI, Get, URLSession background tasks |
| **Image Caching** | SDWebImageSwiftUI, SDWebImage |
| **Persistence & Security** | KeychainStore (Security framework), Local File Storage |
| **Diagnostics & Logging** | LoggingKit (`AppLogger`), StatusOverlayKit |

---

## 📱 Requirements

- **iOS / iPadOS**: 18.0 or later
- **macOS**: 15.0 or later *(Designed for iPad / Mac Catalyst)*
- **tvOS**: 18.0 or later
- **visionOS**: 1.0 or later
- **Xcode**: 16.0 or later
- **Jellyfin Server**: v10.8.0+ (v10.9+ recommended)

---

## 🚀 Getting Started

### 1. Clone the Repository

```bash
git clone https://github.com/GarrettButchko/jellyboi.git
cd jellyboi
```

### 2. Open in Xcode

```bash
open JellyBoi.xcodeproj
```

Xcode will automatically fetch the required Swift Package dependencies defined in the project.

### 3. Build & Run

1. Select your target device (e.g., iPhone 16 Pro Simulator or a physical device).
2. Choose the **JellyBoi** scheme.
3. Press `Cmd + R` to build and run the app.
4. Enter your Jellyfin server URL and log in to begin streaming.

---

## 🏷 Repository Tags & Topics

To optimize project discoverability on GitHub, the following topics/tags are assigned to this project:

```text
jellyfin, jellyfin-client, swift, swiftui, ios, ipados, macos, tvos, visionos,
media-player, video-streaming, ffmpeg, ffmpegkit, avplayer, offline-downloads
```

### Git Release Tagging

To create and push a git release tag:

```bash
# Tag the current release version
git tag -a v1.0.0 -m "Release v1.0.0 - Initial release with offline playback and modern SwiftUI UI"

# Push tag to remote
git push origin v1.0.0
```

---

## 🤝 Contributing

Contributions are welcome! If you encounter a bug, have a feature suggestion, or want to contribute code:

1. Fork the repository.
2. Create a feature branch: `git checkout -b feature/amazing-feature`.
3. Commit your changes: `git commit -m "Add amazing feature"`.
4. Push to the branch: `git push origin feature/amazing-feature`.
5. Open a Pull Request.

---

## 📄 License

This project is licensed under the [GNU General Public License v3.0](LICENSE) with an **Apple App Store Exception** (granting permission to convey and distribute through Apple's App Store under Apple's standard terms) - see the [LICENSE](LICENSE) file for details.
