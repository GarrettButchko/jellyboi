//
//  Carousel.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 8/24/26.
//

import SwiftUI
import BaseColors
import SDWebImage
import SDWebImageSwiftUI
import JellyfinAPI

private let carouselCardWidthRatio: CGFloat = 0.8
private let carouselRestingGap: CGFloat = 0
private let carouselNeighborScale: CGFloat = 0.90
private let carouselAutoScrollInterval: TimeInterval = 9
private let carouselMaxItems: Int = 6

private struct CarouselLoopedItem: Identifiable {
    let id: Int
    let item: BaseItemDto
    let url: URL?
    let isRealSection: Bool
}

private struct AutoScrollTrigger: Equatable {
    let isActive: Bool
    let timerID: UUID
    let animationDisabled: Bool
}

struct Carousel: View {
    let title: String
    let namespace: Namespace.ID
    let backdropURL: (BaseItemDto) -> URL?
    let onSelect: (BaseItemDto) -> Void
    var onSnap: ((Int, BaseItemDto) -> Void)? = nil

    @Environment(HomeViewModel.self) private var viewModel
    @Environment(ViewManager.self) private var viewManager: ViewManager?
    @Environment(\.scenePhase) private var scenePhase

    private var indexAnimation: Animation {
        .smooth(duration: 0.3)
    }

    @State private var currentIndex: Int?
    @State private var snappedIndex: Int
    @State private var hoveredID: Int? = nil
    @State private var timerResetTrigger: UUID = UUID()
    @State private var isAutoScrolling: Bool = false
    @State private var isScrolling: Bool = false
    @State private var pendingTeleportTarget: Int? = nil
    @State private var isScrollVisible: Bool = true
    @State private var isViewVisible: Bool = true
    @State private var lastReportedSnappedIndex: Int? = nil

    private var isTabActive: Bool {
        viewManager?.selectedTab ?? .home == .home
    }

    private var isSceneActive: Bool {
        scenePhase == .active
    }

    /// The carousel is only active when visible in the scroll container, on screen in the active tab,
    /// and the application is in the foreground. This eliminates background timers across other tabs.
    private var isEffectivelyActive: Bool {
        isScrollVisible && isViewVisible && isTabActive && isSceneActive
    }

    init(
        title: String,
        namespace: Namespace.ID,
        initialIndex: Int? = nil,
        backdropURL: @escaping (BaseItemDto) -> URL?,
        onSelect: @escaping (BaseItemDto) -> Void,
        onSnap: ((Int, BaseItemDto) -> Void)? = nil
    ) {
        self.title = title
        self.namespace = namespace
        self.backdropURL = backdropURL
        self.onSelect = onSelect
        self.onSnap = onSnap
        let start = initialIndex ?? 0
        _currentIndex = State(initialValue: initialIndex)
        _snappedIndex = State(initialValue: start)
    }

    // In-progress movies by most absolute time watched, falling back to Recently Added
    // when the user hasn't started anything yet.
    private var items: [BaseItemDto] {
        viewModel.carouselItems
    }

    private func makeLoopedItems(from items: [BaseItemDto]) -> [CarouselLoopedItem] {
        guard !items.isEmpty else { return [] }
        let count = items.count
        let loopStart = count
        var result: [CarouselLoopedItem] = []
        result.reserveCapacity(count * 3)

        // Precompute URLs once per distinct item to avoid repeated URL computation & linear searches
        let itemURLs = items.map { backdropURL($0) }

        // 3 sets: 0..<count (prefix buffer), count..<2*count (main set), 2*count..<3*count (suffix buffer)
        for set in 0..<3 {
            for i in 0..<count {
                let loopedID = set * count + i
                let isReal = loopedID >= loopStart && loopedID < loopStart + count
                result.append(
                    CarouselLoopedItem(
                        id: loopedID,
                        item: items[i],
                        url: itemURLs[i],
                        isRealSection: isReal
                    )
                )
            }
        }
        return result
    }

    private func itemIndex(for loopedID: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return ((loopedID % count) + count) % count
    }

    var body: some View {
        let currentItems = items
        let count = currentItems.count
        let loopedItems = makeLoopedItems(from: currentItems)
        let loopStart = count
        let displayedItemIndex = count == 0 ? 0 : itemIndex(for: snappedIndex, count: count)

        #if DEBUG
        let autoScrollTrigger = AutoScrollTrigger(
            isActive: isEffectivelyActive,
            timerID: timerResetTrigger,
            animationDisabled: DebugSettings.shared.disableCarouselTimerAnimation
        )
        #else
        let autoScrollTrigger = AutoScrollTrigger(
            isActive: isEffectivelyActive,
            timerID: timerResetTrigger,
            animationDisabled: false
        )
        #endif

        VStack(spacing: 12) {
            GeometryReader { geometry in
                let cardWidth = geometry.size.width * carouselCardWidthRatio
                let cardHeight = cardWidth * 9 / 16
                let sideInset = (geometry.size.width - cardWidth) / 2

                ScrollViewReader { proxy in
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: carouselRestingGap) {
                            ForEach(loopedItems) { looped in
                                Button {
                                    if currentIndex == looped.id {
                                        onSelect(looped.item)
                                    } else {
                                        isAutoScrolling = false
                                        timerResetTrigger = UUID()
                                        withAnimation(.smooth(duration: 0.35)) {
                                            currentIndex = looped.id
                                            proxy.scrollTo(looped.id, anchor: .center)
                                        }
                                    }
                                } label: {
                                    cardItem(
                                        looped: looped,
                                        cardWidth: cardWidth,
                                        cardHeight: cardHeight
                                    )
                                }
                                .buttonStyle(.plain)
                                .frame(width: cardWidth, height: cardHeight)
                                .id(looped.id)
                                .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                                    let progress = min(max(abs(phase.value), 0), 1)
                                    let scale = 1.0 - progress * (1.0 - carouselNeighborScale)
                                    return content.scaleEffect(scale)
                                }
                                .onHover { hovering in
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        hoveredID = hovering ? looped.id : nil
                                    }
                                }
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .contentMargins(.horizontal, sideInset, for: .scrollContent)
                    .scrollTargetBehavior(.viewAligned)
                    .scrollPosition(id: $currentIndex, anchor: .center)
                    .scrollIndicators(.hidden)
                    .frame(height: cardHeight)
                    .onAppear {
                        guard count > 0 else { return }
                        let target = viewModel.carouselSnappedIndex ?? loopStart
                        let validTarget = (0..<loopedItems.count).contains(target) ? target : loopStart
                        if lastReportedSnappedIndex == nil {
                            lastReportedSnappedIndex = itemIndex(for: validTarget, count: count)
                        }
                        if currentIndex != validTarget {
                            currentIndex = validTarget
                            snappedIndex = validTarget
                            proxy.scrollTo(validTarget, anchor: .center)
                        }
                    }
                    .task {
                        guard count > 0 else { return }
                        try? await Task.sleep(for: .milliseconds(30))
                        let target = viewModel.carouselSnappedIndex ?? loopStart
                        let validTarget = (0..<loopedItems.count).contains(target) ? target : loopStart
                        if currentIndex != validTarget {
                            currentIndex = validTarget
                            snappedIndex = validTarget
                            proxy.scrollTo(validTarget, anchor: .center)
                        }
                    }
                    .onChange(of: currentIndex) { _, newValue in
                        guard let newValue, newValue != snappedIndex else { return }
                        guard count > 0 else { return }

                        snappedIndex = newValue

                        if newValue < count {
                            pendingTeleportTarget = count + ((newValue % count) + count) % count
                        } else if newValue >= 2 * count {
                            pendingTeleportTarget = count + (newValue % count)
                        } else {
                            pendingTeleportTarget = nil
                        }
                    }
                    .onScrollPhaseChange { oldPhase, newPhase in
                        isScrolling = newPhase.isScrolling
                        if newPhase == .idle {
                            isAutoScrolling = false
                            viewModel.carouselSnappedIndex = snappedIndex
                            let snappedItemIdx = itemIndex(for: snappedIndex, count: count)
                            if lastReportedSnappedIndex != snappedItemIdx {
                                lastReportedSnappedIndex = snappedItemIdx
                                onSnap?(snappedItemIdx, currentItems[snappedItemIdx])
                            }
                            if oldPhase.isScrolling {
                                timerResetTrigger = UUID()
                            }
                        }
                        guard newPhase == .idle, let target = pendingTeleportTarget else { return }
                        pendingTeleportTarget = nil
                        snappedIndex = target
                        currentIndex = target
                        viewModel.carouselSnappedIndex = target
                        proxy.scrollTo(target, anchor: .center)
                    }
                    .onChange(of: count) { _, newCount in
                        guard newCount > 0 else { return }
                        let start = newCount
                        pendingTeleportTarget = nil
                        snappedIndex = start
                        currentIndex = start
                        viewModel.carouselSnappedIndex = start
                        proxy.scrollTo(start, anchor: .center)
                        timerResetTrigger = UUID()
                    }
                    .task(id: autoScrollTrigger) {
                        guard autoScrollTrigger.isActive, !autoScrollTrigger.animationDisabled else { return }
                        guard currentItems.count > 1 else { return }

                        while !Task.isCancelled {
                            try? await Task.sleep(for: .seconds(carouselAutoScrollInterval))
                            guard !Task.isCancelled else { break }
                            guard isEffectivelyActive else { break }
                            isAutoScrolling = true
                            let nextIndex = snappedIndex + 1
                            currentIndex = nextIndex
                            withAnimation(.smooth(duration: 0.45)) {
                                proxy.scrollTo(nextIndex, anchor: .center)
                            }
                            // Allow scroll animation to finish before snapping backdrop
                            try? await Task.sleep(for: .milliseconds(460))
                            guard !Task.isCancelled else { break }
                            isAutoScrolling = false
                            let snappedItemIdx = itemIndex(for: nextIndex, count: count)
                            if snappedItemIdx < currentItems.count {
                                lastReportedSnappedIndex = snappedItemIdx
                                onSnap?(snappedItemIdx, currentItems[snappedItemIdx])
                            }
                        }
                    }
                }
            }
            .aspectRatio(16 / (9 * carouselCardWidthRatio), contentMode: .fit)
            .frame(maxWidth: .infinity)

            #if DEBUG
            let hideIndicator = DebugSettings.shared.hideCarouselIndicator
            #else
            let hideIndicator = false
            #endif

            if !hideIndicator && !currentItems.isEmpty {
                CarouselPageIndicator(
                    count: count,
                    currentIndex: displayedItemIndex,
                    isPaused: !isEffectivelyActive || isScrolling || isAutoScrolling
                )
            }
        }
        .onScrollVisibilityChange(threshold: 0.2) { isScrollVisible = $0 }
        .sensoryFeedback(.selection, trigger: displayedItemIndex)
        .onAppear {
            isViewVisible = true
            let urls = currentItems.compactMap { backdropURL($0) }
            CarouselImageMemoryCache.shared.preloadImages(for: urls)
        }
        .onDisappear {
            isViewVisible = false
        }
        .onChange(of: currentItems.compactMap(\.id)) { _, newIDs in
            let urls = currentItems.compactMap { backdropURL($0) }
            CarouselImageMemoryCache.shared.preloadImages(for: urls)
            if !newIDs.isEmpty {
                let validTarget = (0..<loopedItems.count).contains(snappedIndex) ? snappedIndex : loopStart
                if snappedIndex != validTarget {
                    snappedIndex = validTarget
                    currentIndex = validTarget
                    viewModel.carouselSnappedIndex = validTarget
                    pendingTeleportTarget = nil
                }
            }
        }
    }

    @ViewBuilder
    private func cardItem(
        looped: CarouselLoopedItem,
        cardWidth: CGFloat,
        cardHeight: CGFloat
    ) -> some View {
        let isHovered = hoveredID == looped.id
        let activeIndex = currentIndex ?? snappedIndex
        // Only load images and heavy badge layers within a window of active items
        // so all 18 images aren't loaded and rendered at once
        let shouldLoadContent = abs(looped.id - activeIndex) <= 2
        let cardURL = shouldLoadContent ? looped.url : nil

        Group {
            if looped.id == snappedIndex {
                CarouselCard(
                    item: looped.item,
                    url: cardURL,
                    width: cardWidth,
                    height: cardHeight,
                    shouldLoadContent: shouldLoadContent
                )
                .matchedTransitionSource(
                    id: AnyHashable(looped.item),
                    in: namespace
                )
            } else {
                CarouselCard(
                    item: looped.item,
                    url: cardURL,
                    width: cardWidth,
                    height: cardHeight,
                    shouldLoadContent: shouldLoadContent
                )
            }
        }
        .scaleEffect(isHovered ? 1.05 : 1.0)
        .brightness(isHovered ? 0.06 : 0)
        .animation(.easeInOut(duration: 0.2), value: hoveredID)
    }
}

// MARK: - Page Indicator

private struct ActiveIndicatorPill: View {
    let startDate: Date
    let isPaused: Bool
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: isPaused)) { context in
            let elapsed = max(context.date.timeIntervalSince(startDate), 0)
            let progress = min(elapsed / carouselAutoScrollInterval, 1)
            Canvas { ctx, size in
                guard progress > 0 else { return }
                let trackRect = CGRect(origin: .zero, size: size)
                let radius = size.height / 2
                let fillRect = CGRect(x: 0, y: 0, width: size.width * progress, height: size.height)
                ctx.clip(to: Path(roundedRect: fillRect, cornerRadius: radius))
                ctx.fill(Path(roundedRect: trackRect, cornerRadius: radius), with: .color(Color.mainOpp))
            }
        }
        .frame(width: width, height: height)
    }
}

private struct CarouselPageIndicator: View {
    let count: Int
    let currentIndex: Int
    var isPaused: Bool = false

    private let dotSize: CGFloat = 6
    private let activePillWidth: CGFloat = 20

    @State private var previousIndex: Int = 0
    @State private var startDate: Date = .now

    private var isWrapTransition: Bool {
        guard count > 1 else { return false }
        return (previousIndex == count - 1 && currentIndex == 0) ||
               (previousIndex == 0 && currentIndex == count - 1)
    }

    private var indicatorAnimation: Animation {
        if isWrapTransition {
            return .spring(response: 0.44, dampingFraction: 0.78)
        } else {
            return .spring(response: 0.36, dampingFraction: 0.74)
        }
    }

    var body: some View {
        #if DEBUG
        let showTimerAnimation = !DebugSettings.shared.disableCarouselTimerAnimation
        #else
        let showTimerAnimation = true
        #endif

        HStack(spacing: 5) {
            ForEach(0..<count, id: \.self) { i in
                let isActive = i == currentIndex
                let width = isActive ? activePillWidth : dotSize

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.mainOpp.opacity(0.3))
                        .frame(width: width, height: dotSize)

                    if isActive {
                        if showTimerAnimation {
                            ActiveIndicatorPill(
                                startDate: startDate,
                                isPaused: isPaused,
                                width: width,
                                height: dotSize
                            )
                            .transition(.opacity)
                        } else {
                            Capsule()
                                .fill(Color.mainOpp)
                                .frame(width: width, height: dotSize)
                        }
                    }
                }
                .frame(width: width, height: dotSize)
            }
        }
        .animation(indicatorAnimation, value: currentIndex)
        .onAppear {
            previousIndex = currentIndex
            startDate = .now
        }
        .onChange(of: currentIndex) { oldVal, _ in
            previousIndex = oldVal
            startDate = .now
        }
    }
}

// MARK: - Carousel Card

private struct CarouselCard: View {
    let item: BaseItemDto
    let url: URL?
    let width: CGFloat
    let height: CGFloat
    var shouldLoadContent: Bool = true

    @State private var displayImage: UIImage? = nil
    private let outerCornerRadius: CGFloat = 20

    private var watchProgress: Double? {
        item.watchProgress
    }

    var body: some View {
        let currentImage: UIImage? = displayImage ?? (shouldLoadContent ? url.flatMap { CarouselImageMemoryCache.shared.image(for: $0) } : nil)

        ZStack(alignment: .bottomTrailing) {
            placeholder

            if let currentImage {
                Image(uiImage: currentImage)
                    .resizable()
                    .scaledToFill()
            } else if shouldLoadContent, let url {
                WebImage(url: url) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFill()
                    }
                }
                .cancelOnDisappear(true)
                .onSuccess { image, _, _ in
                    displayImage = image
                    CarouselImageMemoryCache.shared.store(image, for: url)
                }
            }

            if shouldLoadContent {
                VStack(alignment: .trailing, spacing: 6) {
                    if AppPreferences.shared.showProgressBar, let progress = watchProgress {
                        ProgressBar(progress: progress, label: item.timeRemainingFormatted)
                    }
                    if let episodeNumber = item.formattedEpisodeNumber {
                        EpisodeBadge(text: episodeNumber)
                    }
                }
                .padding(10)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: outerCornerRadius, style: .continuous))
        .onChange(of: shouldLoadContent) { _, shouldLoad in
            if !shouldLoad {
                displayImage = nil
            }
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: outerCornerRadius, style: .continuous)
            .fill(Color.sub)
            .overlay {
                Image("Jellyboi")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 75, height: 75)
                    .foregroundStyle(Color.mainOpp.opacity(0.05))
                    .rotationEffect(.degrees(45))
            }
    }
}

// MARK: - Carousel Image Memory Cache

final class CarouselImageMemoryCache {
    static let shared = CarouselImageMemoryCache()

    private var memoryCache: [URL: UIImage] = [:]

    private init() {}

    func image(for url: URL) -> UIImage? {
        if let img = memoryCache[url] {
            return img
        }
        let key = SDWebImageManager.shared.cacheKey(for: url)
        if let img = SDImageCache.shared.imageFromMemoryCache(forKey: key) {
            memoryCache[url] = img
            return img
        }
        return nil
    }

    func store(_ image: UIImage, for url: URL) {
        memoryCache[url] = image
    }

    func preloadImages(for urls: [URL]) {
        for url in urls {
            if memoryCache[url] != nil { continue }
            let key = SDWebImageManager.shared.cacheKey(for: url)
            if let img = SDImageCache.shared.imageFromMemoryCache(forKey: key) {
                memoryCache[url] = img
                continue
            }
            // Asynchronously check disk cache and network without blocking main thread
            SDImageCache.shared.queryImage(
                forKey: key,
                options: [],
                context: nil
            ) { [weak self] image, _, _ in
                if let image {
                    Task { @MainActor [weak self] in
                        self?.store(image, for: url)
                    }
                } else {
                    SDWebImageManager.shared.loadImage(
                        with: url,
                        options: [.highPriority],
                        progress: nil
                    ) { image, _, _, _, finished, _ in
                        guard let image, finished else { return }
                        Task { @MainActor [weak self] in
                            self?.store(image, for: url)
                        }
                    }
                }
            }
        }
    }

    func loadImage(for url: URL, completion: ((UIImage?) -> Void)? = nil) {
        if let cached = image(for: url) {
            completion?(cached)
            return
        }

        let key = SDWebImageManager.shared.cacheKey(for: url)
        SDImageCache.shared.queryImage(
            forKey: key,
            options: [],
            context: nil
        ) { [weak self] image, _, _ in
            if let image {
                Task { @MainActor [weak self] in
                    self?.store(image, for: url)
                    completion?(image)
                }
            } else {
                SDWebImageManager.shared.loadImage(
                    with: url,
                    options: [.avoidAutoSetImage, .highPriority],
                    progress: nil
                ) { image, _, _, _, finished, _ in
                    guard let image, finished else { return }
                    Task { @MainActor [weak self] in
                        self?.store(image, for: url)
                        completion?(image)
                    }
                }
            }
        }
    }
}

// MARK: - Carousel Skeleton Placeholder

extension Carousel {
    /// Placeholder skeleton view matching the exact dimensions and layout of the hero carousel.
    struct Placeholder: View {
        var body: some View {
            VStack(spacing: 12) {
                GeometryReader { geometry in
                    let w = geometry.size.width
                    let cardWidth = w > 0 ? w * carouselCardWidthRatio : 300
                    let cardHeight = cardWidth * 9 / 16
                    SkeletonBlock(cornerRadius: 20)
                        .frame(width: cardWidth, height: cardHeight)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .aspectRatio(16 / (9 * carouselCardWidthRatio), contentMode: .fit)
                .frame(maxWidth: .infinity)
                .transaction { $0.animation = nil }

                #if DEBUG
                let hideIndicator = DebugSettings.shared.hideCarouselIndicator
                #else
                let hideIndicator = false
                #endif

                if !hideIndicator {
                    HStack(spacing: 5) {
                        SkeletonBlock(cornerRadius: 3).frame(width: 20, height: 6)
                        SkeletonBlock(cornerRadius: 3).frame(width: 6, height: 6)
                        SkeletonBlock(cornerRadius: 3).frame(width: 6, height: 6)
                        SkeletonBlock(cornerRadius: 3).frame(width: 6, height: 6)
                        SkeletonBlock(cornerRadius: 3).frame(width: 6, height: 6)
                        SkeletonBlock(cornerRadius: 3).frame(width: 6, height: 6)
                    }
                }
            }
            .skeleton()
        }
    }
}
