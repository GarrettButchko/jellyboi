import SwiftUI
import BaseColors
import SDWebImageSwiftUI
import JellyfinAPI

struct MediaView: View {
    @Environment(ServerViewModel.self) private var serverViewModel
    @State private var viewModel = MediaViewModel()
    @State private var scrollOffset: CGFloat = 0
    @State private var headerHeight: CGFloat = 120
    @State private var selectedItem: BaseItemDto?
    @Namespace private var zoomTransition
    
    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 16)]
    private let topID = "TopID"
    
    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            ZStack(alignment: .top) {
                    ScrollView {
                        Color.clear
                            .frame(height: 0)
                            .id(topID)
                        if viewModel.currentItems.isEmpty {
                            if viewModel.isLoading {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                                    .padding(.top, 40)
                            } else if let error = viewModel.errorMessage {
                                errorState(message: error)
                            } else {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                                    .padding(.top, 40)
                            }
                        } else {
                            LazyVGrid(columns: columns, spacing: 16) {
                                ForEach(viewModel.currentItems, id: \.id) { item in
                                    MediaCard(
                                        item: item,
                                        posterURL: serverViewModel.client.flatMap { viewModel.posterURL(for: item, client: $0) },
                                        namespace: zoomTransition
                                    ) {
                                        selectedItem = item
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 16)
                        }
                    }
                    .contentMargins(.top, headerHeight, for: .scrollContent)
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
                        Picker("Filter", selection: $viewModel.filter) {
                            ForEach(MediaFilter.allCases, id: \.self) { filter in
                                Text(filter.title).tag(filter)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(6)
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 25, style: .continuous))
                        .padding(.horizontal, 20)
                    }
                    .onChange(of: viewModel.filter) { _, _ in
                        proxy.scrollTo(topID, anchor: .top)
                    }
                }
            }
            .navigationDestination(item: $selectedItem) { item in
                MediaDetailView(item: item)
                    .navigationTransition(.zoom(sourceID: item, in: zoomTransition))
                    
            }
            .toolbarVisibility(.hidden, for: .navigationBar)
            .background(Color.bg.ignoresSafeArea())
            .task {
                if let client = serverViewModel.client {
                    await viewModel.load(using: client)
                }
            }
        }
    }
    
    private func errorState(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(Color.mainOpp.opacity(0.5))
            Text(message)
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(Color.mainOpp.opacity(0.6))
                .multilineTextAlignment(.center)
            Button("Try Again") {
                Task {
                    if let client = serverViewModel.client {
                        await viewModel.refresh(using: client)
                    }
                }
            }
            .font(.system(.subheadline, design: .rounded, weight: .semibold))
            .foregroundStyle(Color.bg)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.mainOpp, in: Capsule())
        }
        .padding(.horizontal, 40)
        .padding(.top, 40)
    }
    
}
