//
//  AboutSettingsView.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 11/04/26.
//

import SwiftUI
import BaseColors

struct AboutSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    private var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    private struct DependencyItem: Identifiable {
        let id = UUID()
        let name: String
        let description: String
        let license: String
    }

    private let dependencies: [DependencyItem] = [
        DependencyItem(name: "JellyfinAPI", description: "Official Swift SDK and OpenAPI models for Jellyfin.", license: "GPL-3.0"),
        DependencyItem(name: "FFmpegKit", description: "On-device hardware-accelerated media inspection and remuxing.", license: "LGPL-3.0"),
        DependencyItem(name: "SDWebImageSwiftUI", description: "High-performance image caching and progressive decoding.", license: "MIT"),
        DependencyItem(name: "StatusOverlayKit", description: "Transient pill status overlays and notifications.", license: "MIT"),
        DependencyItem(name: "LoggingKit", description: "Lightweight structured logging with log level filtering.", license: "MIT"),
        DependencyItem(name: "SkeletonUI", description: "Shimmer skeleton loading placeholders for SwiftUI.", license: "MIT"),
        DependencyItem(name: "MarqueeText", description: "Smooth auto-scrolling text for titles and subtitles.", license: "MIT"),
        DependencyItem(name: "BaseColors", description: "Adaptive semantic color palette and dark mode tokens.", license: "Proprietary")
    ]

    var body: some View {
        List {
            // MARK: - App Identity Header
            Section {
                VStack(spacing: 12) {
                    Image("appIcon")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 80, height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)

                    VStack(spacing: 4) {
                        Text("JellyBoi")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(Color.mainOpp)

                        Text("Version \(appVersion) (\(appBuild))")
                            .font(.footnote)
                            .foregroundStyle(Color.mainOpp.opacity(0.6))

                        Text("A native, lightweight Jellyfin client for iOS & iPadOS.")
                            .font(.caption)
                            .foregroundStyle(Color.mainOpp.opacity(0.5))
                            .multilineTextAlignment(.center)
                            .padding(.top, 4)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }

            // MARK: - Links
            Section {
                Link(destination: URL(string: "https://jellyfin.org")!) {
                    HStack {
                        Text("Jellyfin Project")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.mainOpp.opacity(0.4))
                    }
                }

                Link(destination: URL(string: "https://github.com/jellyfin/jellyfin")!) {
                    HStack {
                        Text("Jellyfin Server GitHub")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.mainOpp.opacity(0.4))
                    }
                }
            } header: {
                Text("Official Links")
            }

            // MARK: - Open Source Acknowledgments
            Section {
                ForEach(dependencies) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(item.name)
                                .foregroundStyle(Color.mainOpp)
                            Spacer()
                            Text(item.license)
                                .font(.caption2)
                                .foregroundStyle(Color.mainOpp.opacity(0.5))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.subTwo, in: Capsule())
                        }
                        Text(item.description)
                            .font(.caption)
                            .foregroundStyle(Color.mainOpp.opacity(0.6))
                    }
                    .padding(.vertical, 3)
                }
            } header: {
                Text("Third-Party Acknowledgments")
            } footer: {
                Text("JellyBoi is built with open source software. Jellyfin is a trademark of the Jellyfin project.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.bg.ignoresSafeArea())
        .navigationTitle("About JellyBoi")
        .navigationBarTitleDisplayMode(.inline)
    }
}
