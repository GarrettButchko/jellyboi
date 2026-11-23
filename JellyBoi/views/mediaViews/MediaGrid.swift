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

    let itemIDs: [String]
    var title: String? = nil
    var namespace: Namespace.ID? = nil
    var onSelect: ((String) -> Void)? = nil

    init(
        itemIDs: [String],
        title: String? = nil,
        namespace: Namespace.ID? = nil,
        onSelect: ((String) -> Void)? = nil
    ) {
        self.itemIDs = itemIDs
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
                ForEach(itemIDs, id: \.self) { itemID in
                    let item = LibraryViewModel.shared.item(for: itemID)
                    MediaCard(
                        itemID: itemID,
                        posterURL: item.flatMap { posterURL(for: $0, client: serverViewModel?.client) },
                        namespace: namespace,
                        onSelect: {
                            onSelect?(itemID)
                        },
                        imageAspectRatio: item?.type == .episode ? MediaAspectRatio.poster : nil
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
