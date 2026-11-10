//
//  MediaGrid.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 10/27/26.
//

import SwiftUI
import JellyfinAPI

struct MediaGrid: View {
    @Environment(ServerViewModel.self) private var serverViewModel: ServerViewModel?
    @Environment(\.horizontalSizeClass) private var sizeClass

    let items: [BaseItemDto]
    var namespace: Namespace.ID? = nil
    var onSelect: ((BaseItemDto) -> Void)? = nil

    init(
        items: [BaseItemDto],
        namespace: Namespace.ID? = nil,
        onSelect: ((BaseItemDto) -> Void)? = nil
    ) {
        self.items = items
        self.namespace = namespace
        self.onSelect = onSelect
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: sizeClass == .regular ? 160 : 110), spacing: 16)]
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(items, id: \.id) { item in
                MediaCard(
                    item: item,
                    posterURL: posterURL(for: item, client: serverViewModel?.client),
                    namespace: namespace,
                    onSelect: {
                        onSelect?(item)
                    },
                    imageAspectRatio: item.type == .episode ? (2.0 / 3.0) : nil
                )
                .equatable()
            }
        }
        .padding(.horizontal, 16)
    }

    private func posterURL(for item: BaseItemDto, client: JellyfinClient?) -> URL? {
        if item.type == .episode {
            return item.seriesPosterURL(client: client)
                ?? item.posterURL(client: client)
        }
        return item.posterURL(client: client)
    }
}

// MARK: - Skeleton Placeholder Factory

extension MediaGrid {
    /// Convenience factory rendering a static skeleton placeholder grid.
    static func placeholder(
        count: Int = 18,
        namespace: Namespace.ID? = nil
    ) -> some View {
        MediaGrid(items: .placeholders(count: count), namespace: namespace)
            .skeleton()
    }
}
