//
//  MediaGrid.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 10/27/26.
//

import SwiftUI
import JellyfinAPI

struct MediaGrid: View {
    @Environment(ServerViewModel.self) private var serverViewModel
    @Environment(LibraryViewModel.self) private var libraryViewModel
    @Environment(\.horizontalSizeClass) private var sizeClass

    let items: [BaseItemDto]
    let namespace: Namespace.ID
    let onSelect: (BaseItemDto) -> Void

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: sizeClass == .regular ? 160 : 110), spacing: 16)]
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(items, id: \.id) { item in
                MediaCard(
                    item: item,
                    posterURL: serverViewModel.client.flatMap { client in
                        posterURL(for: item, client: client)
                    },
                    namespace: namespace,
                    onSelect: {
                        onSelect(item)
                    },
                    imageAspectRatio: item.type == .episode ? (2.0 / 3.0) : nil
                )
            }
        }
        .padding(.horizontal, 16)
    }

    private func posterURL(for item: BaseItemDto, client: JellyfinClient) -> URL? {
        if item.type == .episode {
            return libraryViewModel.seriesPosterURL(for: item, client: client)
                ?? libraryViewModel.posterURL(for: item, client: client)
        }
        return libraryViewModel.posterURL(for: item, client: client)
    }
}
