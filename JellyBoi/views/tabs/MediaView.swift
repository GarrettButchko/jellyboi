import SwiftUI
import BaseColors
import SDWebImageSwiftUI
import JellyfinAPI

struct MediaView: View {
    @Environment(ServerViewModel.self) private var serverViewModel
    @Environment(LibraryViewModel.self) private var libraryViewModel
    @Environment(MediaViewModel.self) private var viewModel
    @State private var scrollOffset: CGFloat = 0
    @State private var headerHeight: CGFloat = 120
    @State private var selectedItem: BaseItemDto?
    @State private var sttButtonHeight: CGFloat = 0
    @Namespace private var zoomTransition
    
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: sizeClass == .regular ? 160 : 110), spacing: 16)]
    }
    private let topID = "TopID"
    
    var body: some View {
        @Bindable var viewModel = viewModel
        NavigationStack {
            ScrollViewReader { proxy in
            ZStack(alignment: .top) {
                    ScrollView {
                        Color.clear
                            .frame(height: 0)
                            .id(topID)
                        if viewModel.currentItems.isEmpty {
                            if viewModel.isLoading {
                                SkeletonMediaGrid()
                                    .transition(.opacity)
                            } else if viewModel.showFavoritesOnly && viewModel.hasBaseItems {
                                // Library loaded fine — favorites filter just returned nothing.
                                EmptyStateView(
                                    icon: "star",
                                    title: "No Favorites",
                                    message: "You haven't starred any \(viewModel.filter.title.lowercased()) yet."
                                )
                            } else if let error = viewModel.errorMessage {
                                EmptyStateView(
                                    icon: "wifi.exclamationmark",
                                    title: "Couldn't load library",
                                    message: error,
                                    buttonTitle: "Try Again"
                                ) {
                                    Task {
                                        if let client = serverViewModel.client {
                                            await viewModel.refresh(using: client)
                                        }
                                    }
                                }
                            } else {
                                EmptyStateView(
                                    icon: viewModel.filter == .movies ? "film" : "tv",
                                    title: "No \(viewModel.filter.title)",
                                    message: "Nothing here yet. Pull to refresh or add media to your Jellyfin server.",
                                    buttonTitle: "Refresh"
                                ) {
                                    Task {
                                        if let client = serverViewModel.client {
                                            await viewModel.refresh(using: client)
                                        }
                                    }
                                }
                            }
                        } else {
                            LazyVGrid(columns: columns, spacing: 16) {
                                ForEach(viewModel.currentItems, id: \.id) { item in
                                    MediaCard(
                                        item: item,
                                        posterURL: serverViewModel.client.flatMap { libraryViewModel.posterURL(for: item, client: $0) },
                                        namespace: zoomTransition
                                    ) {
                                        selectedItem = item
                                    }
                                }
                            }
                            .id(viewModel.filter)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)
                            .transition(.opacity)
                            

                        }
                    }
                    .animation(.smooth(duration: 0.3), value: viewModel.filter)
                    .contentMargins(.top, headerHeight, for: .scrollContent)
                    .contentMargins(.bottom, sttButtonHeight, for: .scrollContent)
                    .onScrollGeometryChange(for: CGFloat.self) { geometry in
                        geometry.contentOffset.y + geometry.contentInsets.top
                    } action: { _, newValue in
                        scrollOffset = newValue
                    }
                    .refreshable {
                        if let client = serverViewModel.client {
                            await viewModel.refresh(using: client)
                        }
                    }
                    
                    // Fixed top header overlay
                    TabPageHeader(title: "Library", scrollOffset: scrollOffset, headerHeight: $headerHeight) {
                        HStack(spacing: 10) {
                            Picker("Filter", selection: $viewModel.filter) {
                                ForEach(MediaFilter.allCases, id: \.self) { filter in
                                    Text(filter.title).tag(filter)
                                }
                            }
                            .pickerStyle(.segmented)
                            .padding(6)
                            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 25, style: .continuous))

                            Button {
                                viewModel.showFavoritesOnly.toggle()
                            } label: {
                                Image(systemName: viewModel.showFavoritesOnly ? "star.fill" : "star")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(viewModel.showFavoritesOnly ? Color.yellow : Color.mainOpp)
                                    .frame(width: 44, height: 44)
                                    .glassEffect(.regular.interactive(), in: Circle())
                                    .contentShape(Circle())
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 16)
                    }
                    .onChange(of: viewModel.filter) { _, _ in
                        proxy.scrollTo(topID, anchor: .top)
                        viewModel.showFavoritesOnly = false
                    }

                    ScrollToTopOverlay(scrollOffset: scrollOffset, STTButtonHeight: $sttButtonHeight) {
                        withAnimation { proxy.scrollTo(topID, anchor: .top) }
                    }
                }
            }
            .navigationDestination(item: $selectedItem) { item in
                MediaDetailView(item: item)
                    .navigationTransition(.zoom(sourceID: item, in: zoomTransition))
                    
            }
            .toolbarVisibility(.hidden, for: .navigationBar)
            .background(Color.bg.ignoresSafeArea())
        }
    }
    

}
