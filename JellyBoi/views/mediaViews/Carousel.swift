//
//  Carousel.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 8/29/26.
//

import SwiftUI
import BaseColors
import SDWebImageSwiftUI
import JellyfinAPI
import SDWebImage

// MARK: - Layout Constants

private let carouselRestingGap: CGFloat = 16
private let carouselNeighborScale: CGFloat = 0.95
private let carouselCardWidthRatio: CGFloat = 0.8
private let carouselAutoScrollInterval: TimeInterval = 6.0

// MARK: - Carousel Memory Cache

@MainActor
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
        let key = SDWebImageManager.shared.cacheKey(for: url)
        SDImageCache.shared.store(image, forKey: key, toDisk: true)
    }

    func preloadImages(for urls: [URL]) {
        for url in urls {
            if image(for: url) != nil { continue }
            loadImage(for: url) { _ in }
        }
    }

    func loadImage(for url: URL, completion: (@Sendable @MainActor (UIImage?) -> Void)? = nil) {
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
                ) { [weak self] image, _, _, _, finished, _ in
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

// MARK: - Carousel

private struct CarouselLoopedItem: Identifiable {
    let id: Int
    let itemID: String
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
    let onSelect: (String) -> Void
    var onSnap: ((Int, String) -> Void)? = nil

    @Environment(HomeTabViewModel.self) private var viewModel
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

    private var isEffectivelyActive: Bool {
        isScrollVisible && isViewVisible && isTabActive && isSceneActive
    }

    init(
        title: String,
        namespace: Namespace.ID,
        initialIndex: Int? = nil,
        backdropURL: @escaping (BaseItemDto) -> URL?,
        onSelect: @escaping (String) -> Void,
        onSnap: ((Int, String) -> Void)? = nil
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

    private var itemIDs: [String] {
        viewModel.carouselItemIDs
    }

    private func makeLoopedItems(from ids: [String]) -> [CarouselLoopedItem] {
        guard !ids.isEmpty else { return [] }
        let count = ids.count
        let loopStart = count
        var result: [CarouselLoopedItem] = []
        result.reserveCapacity(count * 3)

        let itemURLs = ids.map { id in
            LibraryViewModel.shared.item(for: id).flatMap { backdropURL($0) }
        }

        for set in 0..<3 {
            for i in 0..<count {
                let loopedID = set * count + i
                let isReal = loopedID >= loopStart && loopedID < loopStart + count
                let itemID = ids[i]
                result.append(
                    CarouselLoopedItem(
                        id: loopedID,
                        itemID: itemID,
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
        let currentItemIDs = itemIDs
        let count = currentItemIDs.count
        let loopedItems = makeLoopedItems(from: currentItemIDs)
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
                let cardHeight = cardWidth / MediaAspectRatio.thumbnail
                let sideInset = (geometry.size.width - cardWidth) / 2

                ScrollViewReader { proxy in
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: carouselRestingGap) {
                            ForEach(loopedItems) { looped in
                                Button {
                                    if currentIndex == looped.id {
                                        onSelect(looped.itemID)
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
                            let initialIdx = itemIndex(for: validTarget, count: count)
                            lastReportedSnappedIndex = initialIdx
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

                        // Immediately blend backdrop and notify selection as index changes
                        let snappedItemIdx = itemIndex(for: newValue, count: count)
                        if lastReportedSnappedIndex != snappedItemIdx {
                            lastReportedSnappedIndex = snappedItemIdx
                            onSnap?(snappedItemIdx, currentItemIDs[snappedItemIdx])
                        }

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
                                onSnap?(snappedItemIdx, currentItemIDs[snappedItemIdx])
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
                        guard currentItemIDs.count > 1 else { return }

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
                            try? await Task.sleep(for: .milliseconds(460))
                            guard !Task.isCancelled else { break }
                            isAutoScrolling = false
                        }
                    }
                }
            }
            .aspectRatio(MediaAspectRatio.thumbnail / carouselCardWidthRatio, contentMode: .fit)
            .frame(maxWidth: .infinity)

            #if DEBUG
            let hideIndicator = DebugSettings.shared.hideCarouselIndicator
            #else
            let hideIndicator = false
            #endif

            if !hideIndicator && !currentItemIDs.isEmpty {
                CarouselPageIndicator(
                    count: count,
                    currentIndex: displayedItemIndex,
                    isPaused: !isEffectivelyActive || isScrolling || isAutoScrolling,
                    timerResetTrigger: timerResetTrigger
                )
            }
        }
        .onScrollVisibilityChange(threshold: 0.2) { isScrollVisible = $0 }
        .sensoryFeedback(.selection, trigger: displayedItemIndex)
        .onAppear {
            isViewVisible = true
            let urls = currentItemIDs.compactMap { id in
                LibraryViewModel.shared.item(for: id).flatMap { backdropURL($0) }
            }
            CarouselImageMemoryCache.shared.preloadImages(for: urls)
        }
        .onDisappear {
            isViewVisible = false
        }
        .onChange(of: currentItemIDs) { _, newIDs in
            let urls = newIDs.compactMap { id in
                LibraryViewModel.shared.item(for: id).flatMap { backdropURL($0) }
            }
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
        let shouldLoadContent = abs(looped.id - activeIndex) <= 2
        let cardURL = shouldLoadContent ? looped.url : nil

        Group {
            if let item = LibraryViewModel.shared.item(for: looped.itemID) {
                if looped.id == snappedIndex {
                    CarouselCard(
                        itemID: looped.itemID,
                        url: cardURL,
                        width: cardWidth,
                        height: cardHeight,
                        shouldLoadContent: shouldLoadContent
                    )
                    .matchedTransitionSource(
                        id: item.zoomTransitionID(isCarousel: true),
                        in: namespace
                    )
                } else {
                    CarouselCard(
                        itemID: looped.itemID,
                        url: cardURL,
                        width: cardWidth,
                        height: cardHeight,
                        shouldLoadContent: shouldLoadContent
                    )
                }
            } else {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.mainOpp.opacity(0.06))
                    .frame(width: cardWidth, height: cardHeight)
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
    let isPaused: Bool
    var timerResetTrigger: UUID = UUID()

    @State private var pillStartDate: Date = Date()
    @State private var previousIndex: Int = 0

    private let activePillWidth: CGFloat = 20
    private let dotSize: CGFloat = 6
    private let height: CGFloat = 6

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
            ForEach(0..<count, id: \.self) { index in
                let isActive = index == currentIndex
                let width = isActive ? activePillWidth : dotSize

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.mainOpp.opacity(isActive ? 0.2 : 0.3))
                        .frame(width: width, height: height)

                    if isActive {
                        if showTimerAnimation {
                            ActiveIndicatorPill(
                                startDate: pillStartDate,
                                isPaused: isPaused,
                                width: width,
                                height: height
                            )
                            .transition(.opacity)
                        } else {
                            Capsule()
                                .fill(Color.mainOpp)
                                .frame(width: width, height: height)
                        }
                    }
                }
                .clipShape(Capsule())
                .frame(width: width, height: height)
            }
        }
        .padding(.vertical, 4)
        .animation(indicatorAnimation, value: currentIndex)
        .onChange(of: currentIndex) { oldVal, newVal in
            previousIndex = oldVal
            if oldVal != newVal {
                pillStartDate = Date()
            }
        }
        .onChange(of: timerResetTrigger) { _, _ in
            pillStartDate = Date()
        }
        .onAppear {
            previousIndex = currentIndex
            pillStartDate = Date()
        }
    }
}

// MARK: - Carousel Card

private struct CarouselCard: View {
    let itemID: String
    let url: URL?
    let width: CGFloat
    let height: CGFloat
    let shouldLoadContent: Bool

    @State private var displayImage: UIImage? = nil
    private let outerCornerRadius: CGFloat = 16

    private var item: BaseItemDto? {
        LibraryViewModel.shared.item(for: itemID)
    }

    private var watchProgress: Double? {
        item?.watchProgress
    }

    var body: some View {
        let cachedImage = url.flatMap { CarouselImageMemoryCache.shared.image(for: $0) }
        let currentImage = displayImage ?? cachedImage

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

            if shouldLoadContent, let item {
                VStack(alignment: .trailing, spacing: 6) {
                    if AppPreferences.shared.showProgressBar,
                       let progress = watchProgress,
                       !item.isWatched && item.isInProgress && Int(progress * 100) > 0 {
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
        .task(id: url) {
            guard let url else { return }
            if let cached = CarouselImageMemoryCache.shared.image(for: url) {
                if displayImage !== cached {
                    displayImage = cached
                }
            } else {
                CarouselImageMemoryCache.shared.loadImage(for: url) { image in
                    if let image {
                        displayImage = image
                    }
                }
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

extension Carousel {
    typealias Placeholder = CarouselSkeleton
}
