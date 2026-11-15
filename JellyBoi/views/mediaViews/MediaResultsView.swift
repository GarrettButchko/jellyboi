//
//  MediaResultsView.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 10/8/26.
//

import SwiftUI
import JellyfinAPI
import BaseColors
internal import Combine

struct MediaResultsView: View {
    enum Category {
        case genre(String)
        case collections
        case custom(title: String, emptyIcon: String, emptyTitle: String, emptyMessage: String)
    }

    let category: Category
    let itemIDs: [String]

    init(category: Category, itemIDs: [String]) {
        self.category = category
        self.itemIDs = itemIDs
    }

    init(genre: String, itemIDs: [String]) {
        self.category = .genre(genre)
        self.itemIDs = itemIDs
    }

    init(collections itemIDs: [String]) {
        self.category = .collections
        self.itemIDs = itemIDs
    }

    init(
        title: String,
        itemIDs: [String],
        emptyIcon: String = "film",
        emptyTitle: String = "No Items",
        emptyMessage: String = "No items found."
    ) {
        self.category = .custom(title: title, emptyIcon: emptyIcon, emptyTitle: emptyTitle, emptyMessage: emptyMessage)
        self.itemIDs = itemIDs
    }

    var title: String {
        switch category {
        case .genre(let name): name
        case .collections: "Collections"
        case .custom(let title, _, _, _): title
        }
    }

    var emptyIcon: String {
        switch category {
        case .genre: "film"
        case .collections: "square.stack.3d.up"
        case .custom(_, let icon, _, _): icon
        }
    }

    var emptyTitle: String {
        switch category {
        case .genre: "No Titles in Genre"
        case .collections: "No Collections"
        case .custom(_, _, let title, _): title
        }
    }

    var emptyMessage: String {
        switch category {
        case .genre(let name): "No movies or shows found for \(name)."
        case .collections: "No box sets or collections found in your library."
        case .custom(_, _, _, let message): message
        }
    }

    @Environment(LibraryViewModel.self) private var libraryViewModel: LibraryViewModel?
    @Namespace private var zoomTransition
    @State private var selectedItemID: String?

    var body: some View {
        ScrollToTopScrollView {
            if itemIDs.isEmpty {
                EmptyStateView(
                    icon: emptyIcon,
                    title: emptyTitle,
                    message: emptyMessage
                )
            } else {
                MediaGrid(itemIDs: itemIDs, namespace: zoomTransition) { itemID in
                    selectedItemID = itemID
                }
                .transition(.opacity)
            }
        }
        .navigationDestination(item: $selectedItemID) { itemID in
            if let item = libraryViewModel?.item(for: itemID) {
                MediaDetailView(item: item)
                    .navigationTransition(.zoom(sourceID: item.zoomTransitionID(), in: zoomTransition))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .dismissMediaDetailToRoot)) { _ in
            selectedItemID = nil
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.large)
        .background(Color.bg.ignoresSafeArea())
    }
}
