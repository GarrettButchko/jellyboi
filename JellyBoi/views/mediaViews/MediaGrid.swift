//
//  MediaGrid.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 10/27/26.
//

import SwiftUI
import BaseColors
import JellyfinAPI

struct MediaGrid: View {
    @Environment(ServerViewModel.self) private var serverViewModel: ServerViewModel?
    @Environment(\.horizontalSizeClass) private var sizeClass

    let items: [BaseItemDto]
    var title: String? = nil
    var namespace: Namespace.ID? = nil
    var onSelect: ((BaseItemDto) -> Void)? = nil

    init(
        items: [BaseItemDto],
        title: String? = nil,
        namespace: Namespace.ID? = nil,
        onSelect: ((BaseItemDto) -> Void)? = nil
    ) {
        self.items = items
        self.title = title
        self.namespace = namespace
        self.onSelect = onSelect
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: sizeClass == .regular ? 160 : 110), spacing: 16)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Text(title)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color.mainOpp)
                    .padding(.horizontal, 16)
            }

            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(items, id: \.id) { item in
                    MediaCard(
                        item: item,
                        posterURL: posterURL(for: item, client: serverViewModel?.client),
                        namespace: namespace,
                        onSelect: {
                            onSelect?(item)
                        },
                        imageAspectRatio: item.type == .episode ? MediaAspectRatio.poster : nil
                    )
                    .equatable()
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func posterURL(for item: BaseItemDto, client: JellyfinClient?) -> URL? {
        if item.type == .episode {
            return item.seriesPosterURL(client: client)
                ?? item.posterURL(client: client)
        }
        return item.posterURL(client: client)
    }
}
