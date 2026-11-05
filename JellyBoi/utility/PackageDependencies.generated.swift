//
//  PackageDependencies.generated.swift
//  JellyBoi
//
//  Generated at compile time from Package.resolved and project.pbxproj.
//  DO NOT EDIT MANUALLY - Automatically regenerated on build.
//

import Foundation

public struct DependencyItem: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let version: String?
    public let url: URL?

    public init(
        id: String? = nil,
        name: String,
        version: String? = nil,
        url: URL? = nil
    ) {
        self.id = id ?? name
        self.name = name
        self.version = version
        self.url = url
    }

    public var hasGitHubLink: Bool {
        guard let url, let host = url.host?.lowercased() else { return false }
        return host.contains("github.com")
    }
}

public enum PackageDependencies {
    public static let all: [DependencyItem] = [
        DependencyItem(
            id: "ffmpegkit",
            name: "Ffmpegkit",
            version: "9.0.2",
            url: URL(string: "https://github.com/kingslay/FFmpegKit")
        ),
        DependencyItem(
            id: "get",
            name: "Get",
            version: "2.2.1",
            url: URL(string: "https://github.com/kean/Get")
        ),
        DependencyItem(
            id: "jellyfin-sdk-swift",
            name: "Jellyfin Sdk Swift",
            version: "3.0.0",
            url: URL(string: "https://github.com/jellyfin/jellyfin-sdk-swift")
        ),
        DependencyItem(
            id: "marqueetext",
            name: "Marqueetext",
            version: "master",
            url: URL(string: "https://github.com/joekndy/MarqueeText")
        ),
        DependencyItem(
            id: "scalingheaderscrollview",
            name: "Scalingheaderscrollview",
            version: "3.0.0",
            url: URL(string: "https://github.com/exyte/ScalingHeaderScrollView")
        ),
        DependencyItem(
            id: "sdwebimage",
            name: "Sdwebimage",
            version: "5.21.7",
            url: URL(string: "https://github.com/SDWebImage/SDWebImage")
        ),
        DependencyItem(
            id: "sdwebimageswiftui",
            name: "Sdwebimageswiftui",
            version: "3.1.4",
            url: URL(string: "https://github.com/SDWebImage/SDWebImageSwiftUI")
        ),
        DependencyItem(
            id: "skeletonui",
            name: "Skeletonui",
            version: "2.0.2",
            url: URL(string: "https://github.com/CSolanaM/SkeletonUI")
        ),
        DependencyItem(
            id: "swift-atomics",
            name: "Swift Atomics",
            version: "1.3.1",
            url: URL(string: "https://github.com/apple/swift-atomics")
        ),
        DependencyItem(
            id: "swift-collections",
            name: "Swift Collections",
            version: "1.7.4",
            url: URL(string: "https://github.com/apple/swift-collections")
        ),
        DependencyItem(
            id: "swift-custom-dump",
            name: "Swift Custom Dump",
            version: "1.7.0",
            url: URL(string: "https://github.com/pointfreeco/swift-custom-dump")
        ),
        DependencyItem(
            id: "swift-issue-reporting",
            name: "Swift Issue Reporting",
            version: "2.1.0",
            url: URL(string: "https://github.com/pointfreeco/swift-issue-reporting")
        ),
        DependencyItem(
            id: "swift-nio",
            name: "Swift Nio",
            version: "2.104.0",
            url: URL(string: "https://github.com/apple/swift-nio")
        ),
        DependencyItem(
            id: "swift-nio-transport-services",
            name: "Swift Nio Transport Services",
            version: "1.28.0",
            url: URL(string: "https://github.com/apple/swift-nio-transport-services")
        ),
        DependencyItem(
            id: "swift-snapshot-testing",
            name: "Swift Snapshot Testing",
            version: "1.19.4",
            url: URL(string: "https://github.com/pointfreeco/swift-snapshot-testing")
        ),
        DependencyItem(
            id: "swift-syntax",
            name: "Swift Syntax",
            version: "603.0.2",
            url: URL(string: "https://github.com/swiftlang/swift-syntax")
        ),
        DependencyItem(
            id: "swift-system",
            name: "Swift System",
            version: "1.8.1",
            url: URL(string: "https://github.com/apple/swift-system")
        ),
        DependencyItem(
            id: "xctest-dynamic-overlay",
            name: "Xctest Dynamic Overlay",
            version: "1.13.1",
            url: URL(string: "https://github.com/pointfreeco/xctest-dynamic-overlay")
        ),
    ]
}
