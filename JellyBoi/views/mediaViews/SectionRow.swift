//
//  SectionRow.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 8/31/26.
//

import SwiftUI
import BaseColors
import JellyfinAPI

/// A reusable section container with a bold section title, optional trailing header accessory,
/// and customizable row content. Used across Home and MediaDetail views (episodes, cast & crew,
/// special features, more like this, etc.).
struct SectionRow<Content: View, HeaderAccessory: View>: View {
    let title: String
    var onTitleTap: (() -> Void)? = nil
    @ViewBuilder let headerAccessory: () -> HeaderAccessory
    @ViewBuilder let content: () -> Content

    init(
        title: String,
        onTitleTap: (() -> Void)? = nil,
        @ViewBuilder headerAccessory: @escaping () -> HeaderAccessory,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.onTitleTap = onTitleTap
        self.headerAccessory = headerAccessory
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            content()
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            if let onTitleTap {
                Button(action: onTitleTap) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.system(size: 20, weight: .bold))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 15, weight: .bold))
                    }
                    .foregroundStyle(Color.mainOpp)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                Text(title)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color.mainOpp)
            }

            Spacer()

            headerAccessory()
        }
        .padding(.horizontal, 16)
    }
}

// MARK: - SectionRowMediaList

/// Standard horizontal scroll list of `MediaCard` items used by `SectionRow`.
struct SectionRowMediaList: View {
    let itemIDs: [String]
    var namespace: Namespace.ID? = nil
    var rowKey: String? = nil
    var imageAspectRatio: CGFloat? = MediaAspectRatio.poster
    var cardHeight: CGFloat? = nil
    var onSelect: ((String, AnyHashable) -> Void)? = nil
    var posterURL: ((BaseItemDto) -> URL?)? = nil

    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(LibraryViewModel.self) private var libraryViewModel: LibraryViewModel?

    private var defaultCardWidth: CGFloat { sizeClass == .regular ? 160 : 110 }

    private var resolvedCardWidth: CGFloat {
        if let cardHeight {
            return cardHeight * (imageAspectRatio ?? MediaAspectRatio.poster)
        }
        return defaultCardWidth
    }

    private var resolvedCardHeight: CGFloat {
        cardHeight ?? (defaultCardWidth / (imageAspectRatio ?? MediaAspectRatio.poster))
    }

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 16) {
                ForEach(itemIDs, id: \.self) { itemID in
                    let zoomID = rowKey.map { AnyHashable("\($0)-\(itemID)") } ?? AnyHashable(itemID)
                    let item = libraryViewModel?.item(for: itemID)
                    MediaCard(
                        itemID: itemID,
                        posterURL: item.flatMap { posterURL?($0) },
                        namespace: namespace,
                        onSelect: {
                            onSelect?(itemID, zoomID)
                        },
                        zoomID: zoomID,
                        imageAspectRatio: imageAspectRatio
                    )
                    .equatable()
                    .frame(width: resolvedCardWidth, height: resolvedCardHeight)
                }
            }
            .padding(.horizontal, 16)
            .scrollTargetLayout()
        }
        .frame(height: resolvedCardHeight)
        .scrollClipDisabled()
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.viewAligned)
    }
}
