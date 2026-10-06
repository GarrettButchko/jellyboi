//
//  MediaRow.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 8/31/26.
//

import SwiftUI
import BaseColors
import JellyfinAPI

/// A reusable horizontal-scroll row of `MediaCard`s with a bold section title.
/// Used on both the Home screen and the media detail screen.
struct SectionRow: View {
    let title: String
    let items: [BaseItemDto]
    let namespace: Namespace.ID
    var rowKey: String? = nil
    let onSelect: (BaseItemDto, AnyHashable) -> Void
    let posterURL: (BaseItemDto) -> URL?

    @Environment(\.horizontalSizeClass) private var sizeClass

    private var cardWidth: CGFloat { sizeClass == .regular ? 160 : 110 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Color.mainOpp)
                .padding(.horizontal, 16)

            ScrollView(.horizontal) {
                LazyHStack(spacing: 16) {
                    ForEach(items, id: \.id) { item in
                        let zoomID: AnyHashable = rowKey.map { AnyHashable("\($0)-\(item.id ?? "")") } ?? AnyHashable(item)
                        MediaCard(
                            item: item,
                            posterURL: posterURL(item),
                            namespace: namespace,
                            onSelect: {
                                onSelect(item, zoomID)
                            },
                            zoomID: zoomID
                        )
                        .frame(width: cardWidth)
                    }
                }
                .padding(.horizontal, 16)
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
        }
    }
}
