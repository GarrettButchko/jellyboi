import SwiftUI
import BaseColors
import SDWebImageSwiftUI
import JellyfinAPI

struct MediaView: View {
    @Environment(ServerViewModel.self) private var serverViewModel
    @State private var viewModel = MediaViewModel()
    @State private var scrollOffset: CGFloat = 0
    
    // Store measured header height (initialized with a safe fallback)
    @State private var headerHeight: CGFloat = 120
    
    @State private var selectedItem: BaseItemDto?
    @Namespace private var zoomTransition
    
    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 16)]
    private let titleCollapseThreshold: CGFloat = 50
    
    private let topID = "TopID"
    
    private var isTitleHidden: Bool {
        scrollOffset > titleCollapseThreshold
    }
    
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
                                        viewModel: viewModel,
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
                    // Use the dynamically measured expanded header height
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
                    headerContent
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
            .animation(.smooth, value: isTitleHidden)
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
    
    private var headerContent: some View {
        VStack(alignment: .leading, spacing: isTitleHidden ? 0 : 14) {
            if !isTitleHidden {
                HStack(alignment: .center) {
                    Text("Library")
                        .font(.system(.title, design: .rounded, weight: .bold))
                        .foregroundStyle(Color.mainOpp)
                    Spacer()
                    ProfileAvatarButton()
                        .padding(.trailing, -20)
                }
                .padding(.horizontal, 20)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            
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
        .padding(.top, 16)
        .background(
            // Measure the expanded state size on initial layout
            // using a hidden reference template in the background
            Color.clear.background {
                expandedHeaderTemplate
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.height
                    } action: { newHeight in
                        // Update headerHeight only if valid and changed
                        if newHeight > 0 && headerHeight != newHeight {
                            headerHeight = newHeight
                        }
                    }
            }
        )
        .background(
            LinearGradient(
                colors: [Color.bg, Color.bg.opacity(0.8), Color.clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .top)
        )
    }
    
    // Unrendered structural view used purely to capture total expanded height
    private var expandedHeaderTemplate: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                Text("Library")
                    .font(.system(.title, design: .rounded, weight: .bold))
                Spacer()
                Circle()
                    .frame(width: 40, height: 40)
                    .padding(.trailing, -20)
            }
            .padding(.horizontal, 20)
            
            Picker("Filter", selection: .constant(MediaFilter.allCases.first)) {
                ForEach(MediaFilter.allCases, id: \.self) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .padding(6)
            .padding(.horizontal, 20)
        }
        .padding(.vertical, 16)
        .hidden()
    }
}


// MARK: - Media Card

private struct MediaCard: View {
    @Environment(ServerViewModel.self) private var serverViewModel
    
    let item: BaseItemDto
    let viewModel: MediaViewModel
    let namespace: Namespace.ID
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            posterImage
                .aspectRatio(2/3, contentMode: .fit)
                .overlay(alignment: .bottom) {
                    if let progress = watchProgress, !isWatched {
                        progressBar(progress)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if isWatched {
                        watchedBadge
                            .padding(8)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .matchedTransitionSource(id: item, in: namespace)
        .frame(maxHeight: .infinity, alignment: .top)
        
    }

    private var watchProgress: Double? {
        if item.userData?.isPlayed == true { return 1 }
        guard let percent = item.userData?.playedPercentage else { return nil }
        return min(max(percent / 100, 0), 1)
    }

    private var isWatched: Bool {
        (watchProgress ?? 0) >= 0.85
    }

    private var watchedBadge: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(Color.white)
            .frame(width: 22, height: 22)
            .background(Color.accentColor, in: Circle())
    }

    private func progressBar(_ progress: Double) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.accentColor)
                    .frame(width: proxy.size.width * progress)
            }
        }
        .frame(height: 6)
    }

    @ViewBuilder
    private var posterImage: some View {
        if let client = serverViewModel.client,
           let url = viewModel.posterURL(for: item, client: client) {
            WebImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                placeholder
            }
            .frame(maxWidth: .infinity)
        } else {
            placeholder
        }
    }
    
    private var placeholder: some View {
        Color.sub
            .overlay {
                AnimatedImage(name: "jellyFishAniBlack.gif")
                    .playbackRate(2.0)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 50, height: 50)
                    .opacity(0.05)
                    .rotationEffect(Angle(degrees: 45))
            }
    }
}
