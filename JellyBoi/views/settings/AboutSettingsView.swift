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
    @Environment(\.openURL) private var openURL

    private let dependencies: [DependencyItem] = PackageDependencies.all

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    private var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    var body: some View {
        List {
            // MARK: - App Identity Header
            Section {
                VStack(spacing: 12) {
                    Image("Jellyboi")
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 80, height: 80)
                        .rotationEffect(Angle(degrees: 45))
                        .foregroundStyle(Color.mainOpp)

                    VStack(spacing: 4) {
                        Text("JellyBoi")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(Color.mainOpp)

                        Text("Version \(appVersion)")
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
                    dependencyRow(for: item)
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

    @ViewBuilder
    private func dependencyRow(for item: DependencyItem) -> some View {
        if let url = item.url {
            Button {
                openURL(url)
            } label: {
                dependencyRowContent(for: item)
            }
            .buttonStyle(.plain)
        } else {
            dependencyRowContent(for: item)
        }
    }

    @ViewBuilder
    private func dependencyRowContent(for item: DependencyItem) -> some View {
        HStack(spacing: 6) {
            Text(item.name)
                .foregroundStyle(Color.mainOpp)

            if item.hasGitHubLink {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.mainOpp.opacity(0.4))
            }

            Spacer()

            if let version = item.version {
                Text("v\(version)")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Color.mainOpp.opacity(0.7))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.mainOpp.opacity(0.1), in: Capsule())
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}
