//
//  MediaDetailPlaceholder.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 10/30/26.
//

import SwiftUI
import BaseColors
import JellyfinAPI

// MARK: - Detail Placeholder Content

struct MediaDetailPlaceholderContent: View {
    let isSeries: Bool
    let isCollection: Bool
    let hasSpecialFeatures: Bool

    @Environment(\.horizontalSizeClass) private var sizeClass

    private var episodeCardHeight: CGFloat { sizeClass == .regular ? 140 : 120 }
    private var episodeCardWidth: CGFloat { episodeCardHeight * (16.0 / 9.0) }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Overview placeholder lines
            VStack(alignment: .leading, spacing: 8) {
                SkeletonBlock(cornerRadius: 4).frame(maxWidth: .infinity).frame(height: 14)
                SkeletonBlock(cornerRadius: 4).frame(maxWidth: .infinity).frame(height: 14)
                SkeletonBlock(cornerRadius: 4).frame(height: 14).frame(maxWidth: .infinity, alignment: .leading).padding(.trailing, 80)
            }
            .padding(.horizontal, 20)

            // Info chips placeholder
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach([70, 90, 50, 80, 60] as [CGFloat], id: \.self) { w in
                        SkeletonBlock(cornerRadius: 14).frame(width: w, height: 32)
                    }
                }
                .padding(.horizontal, 20)
            }
            .scrollIndicators(.hidden)
            .disabled(true)

            if isSeries {
                SectionRow(title: "Episodes") {
                    ScrollView(.horizontal) {
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(0..<5, id: \.self) { _ in
                                SkeletonBlock(cornerRadius: 16)
                                    .frame(width: episodeCardWidth, height: episodeCardHeight)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .scrollClipDisabled()
                    .scrollIndicators(.hidden)
                }
                .skeleton()
            }

            if isCollection {
                SectionRow(title: "Movies & Shows") {
                    MediaGrid.placeholder(count: 12)
                }
            } else {
                SectionRow(title: "Cast & Crew") {
                    ScrollView(.horizontal) {
                        HStack(alignment: .top, spacing: 16) {
                            ForEach(BaseItemPerson.placeholders(count: 8), id: \.id) { person in
                                CastCircle(person: person, imageURL: nil)
                                    .frame(width: 74, alignment: .top)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .scrollClipDisabled()
                    .scrollIndicators(.hidden)
                }
                .skeleton()

                if hasSpecialFeatures {
                    SectionRow.placeholder(
                        title: "Special Features",
                        count: 4,
                        imageAspectRatio: 16.0 / 9.0
                    )
                }

                SectionRow.placeholder(
                    title: "More Like This",
                    count: 8
                )
            }
        }
        .padding(.top, 16)
        .padding(.bottom, 48)
    }
}

#Preview {
    ZStack {
        Color.bg.ignoresSafeArea()
        ScrollView {
            MediaDetailPlaceholderContent(
                isSeries: true,
                isCollection: false,
                hasSpecialFeatures: true
            )
        }
    }
}
