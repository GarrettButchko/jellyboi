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
    let items: [BaseItemDto]

    init(category: Category, items: [BaseItemDto]) {
        self.category = category
        self.items = items
    }

    init(genre: String, items: [BaseItemDto]) {
        self.category = .genre(genre)
        self.items = items
    }

    init(collections items: [BaseItemDto]) {
        self.category = .collections
        self.items = items
    }

    init(
        title: String,
        items: [BaseItemDto],
        emptyIcon: String = "film",
        emptyTitle: String = "No Items",
        emptyMessage: String = "No items found."
    ) {
        self.category = .custom(title: title, emptyIcon: emptyIcon, emptyTitle: emptyTitle, emptyMessage: emptyMessage)
        self.items = items
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

    @Environment(ServerViewModel.self) private var serverViewModel
    @Environment(LibraryViewModel.self) private var libraryViewModel
    @Namespace private var zoomTransition
    @State private var selectedItem: BaseItemDto?
    @State private var scrollOffset: CGFloat = 0
    @State private var headerHeight: CGFloat = 120
    @State private var sttButtonHeight: CGFloat = 0

    @Environment(\.horizontalSizeClass) private var sizeClass
    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: sizeClass == .regular ? 160 : 110), spacing: 16)]
    }

    private let topID = "MediaResultsTopID"

    var body: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .top) {
                ScrollView {
                    Color.clear.frame(height: 0).id(topID)

                    if items.isEmpty {
                        EmptyStateView(
                            icon: emptyIcon,
                            title: emptyTitle,
                            message: emptyMessage
                        )
                    } else {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(items, id: \.id) { item in
                                MediaCard(
                                    item: item,
                                    posterURL: serverViewModel.client.flatMap { libraryViewModel.posterURL(for: item, client: $0) },
                                    namespace: zoomTransition
                                ) {
                                    selectedItem = item
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                        .transition(.opacity)
                    }
                }
                .contentMargins(.top, headerHeight, for: .scrollContent)
                .contentMargins(.bottom, sttButtonHeight, for: .scrollContent)
                .scrollEdgeEffectHidden(scrollOffset <= 0, for: .top)
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentOffset.y + geometry.contentInsets.top
                } action: { _, newValue in
                    scrollOffset = newValue
                }

                TabPageHeader(title: title, scrollOffset: scrollOffset, headerHeight: $headerHeight, showBackButton: true)

                ScrollToTopOverlay(scrollOffset: scrollOffset, STTButtonHeight: $sttButtonHeight) {
                    withAnimation { proxy.scrollTo(topID, anchor: .top) }
                }
            }
        }
        .navigationDestination(item: $selectedItem) { item in
            MediaDetailView(item: item)
                .navigationTransition(.zoom(sourceID: item, in: zoomTransition))
        }
        .onReceive(NotificationCenter.default.publisher(for: .dismissMediaDetailToRoot)) { _ in
            selectedItem = nil
        }
        .toolbarVisibility(.hidden, for: .navigationBar)
        .background(Color.bg.ignoresSafeArea())
    }
}
