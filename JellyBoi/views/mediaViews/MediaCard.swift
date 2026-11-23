//
//  MediaCard.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 8/25/26.
//

import SwiftUI
import BaseColors
import SDWebImage
import SDWebImageSwiftUI
import JellyfinAPI

struct MediaCard: View, Equatable {
    let itemID: String?
    let fallbackItem: BaseItemDto?
    let posterURL: URL?
    let namespace: Namespace.ID?
    let onSelect: () -> Void
    var zoomID: AnyHashable? = nil
    var imageAspectRatio: CGFloat? = nil
    var onContinueWatching: (() -> Void)? = nil
    var onStartFromBeginning: (() -> Void)? = nil
    var onResetProgress: (() -> Void)? = nil

    /// Primary ID-based initializer
    init(
        itemID: String,
        posterURL: URL? = nil,
        namespace: Namespace.ID? = nil,
        onSelect: @escaping () -> Void = {},
        zoomID: AnyHashable? = nil,
        imageAspectRatio: CGFloat? = nil,
        onContinueWatching: (() -> Void)? = nil,
        onStartFromBeginning: (() -> Void)? = nil,
        onResetProgress: (() -> Void)? = nil
    ) {
        self.itemID = itemID
        self.fallbackItem = nil
        self.posterURL = posterURL
        self.namespace = namespace
        self.onSelect = onSelect
        self.zoomID = zoomID
        self.imageAspectRatio = imageAspectRatio
        self.onContinueWatching = onContinueWatching
        self.onStartFromBeginning = onStartFromBeginning
        self.onResetProgress = onResetProgress
    }

    /// Direct item initializer for offline or ephemeral items
    init(
        item: BaseItemDto,
        posterURL: URL? = nil,
        namespace: Namespace.ID? = nil,
        onSelect: @escaping () -> Void = {},
        zoomID: AnyHashable? = nil,
        imageAspectRatio: CGFloat? = nil,
        onContinueWatching: (() -> Void)? = nil,
        onStartFromBeginning: (() -> Void)? = nil,
        onResetProgress: (() -> Void)? = nil
    ) {
        self.itemID = item.id
        self.fallbackItem = item
        self.posterURL = posterURL
        self.namespace = namespace
        self.onSelect = onSelect
        self.zoomID = zoomID
        self.imageAspectRatio = imageAspectRatio
        self.onContinueWatching = onContinueWatching
        self.onStartFromBeginning = onStartFromBeginning
        self.onResetProgress = onResetProgress
    }

    @Environment(ServerViewModel.self) private var serverViewModel: ServerViewModel?
    @Environment(PlaybackManager.self) private var playbackManager: PlaybackManager?
    @Environment(\.redactionReasons) private var redactionReasons

    @State private var isHovered: Bool = false
    @State private var isFavoriteOverride: Bool? = nil

    private var resolvedItem: BaseItemDto? {
        if let itemID, let found = LibraryViewModel.shared.item(for: itemID) {
            return found
        }
        return fallbackItem
    }

    static func == (lhs: MediaCard, rhs: MediaCard) -> Bool {
        lhs.itemID == rhs.itemID &&
        lhs.fallbackItem?.id == rhs.fallbackItem?.id &&
        lhs.fallbackItem?.userData?.isPlayed == rhs.fallbackItem?.userData?.isPlayed &&
        lhs.fallbackItem?.userData?.playbackPositionTicks == rhs.fallbackItem?.userData?.playbackPositionTicks &&
        lhs.fallbackItem?.userData?.isFavorite == rhs.fallbackItem?.userData?.isFavorite &&
        lhs.fallbackItem?.userData?.unplayedItemCount == rhs.fallbackItem?.userData?.unplayedItemCount &&
        lhs.posterURL == rhs.posterURL &&
        lhs.zoomID == rhs.zoomID &&
        lhs.imageAspectRatio == rhs.imageAspectRatio
    }

    private var isFavorite: Bool {
        isFavoriteOverride ?? resolvedItem?.isFavorite ?? false
    }

    private var isRedacted: Bool {
        redactionReasons.contains(.placeholder)
    }

    private var effectiveAspectRatio: CGFloat {
        imageAspectRatio ?? resolvedItem?.imageAspectRatio ?? MediaAspectRatio.poster
    }

    /// Single-pass calculation of watched, watching, and progress to avoid redundant calculations during scrolling.
    private func computeWatchState(for item: BaseItemDto) -> (isWatched: Bool, isWatching: Bool, watchProgress: Double?) {
        let watched: Bool
        if item.type == .series {
            watched = item.isSeriesWatched()
        } else {
            watched = item.isWatched
        }

        if watched {
            return (true, false, 1.0)
        }

        let watching: Bool
        let progress: Double?
        if item.type == .series {
            watching = item.isSeriesInProgress()
            progress = watching ? item.seriesWatchProgress() : nil
        } else {
            watching = item.isInProgress
            progress = watching ? item.watchProgress : nil
        }

        return (false, watching, progress)
    }

    private func playAction(fromBeginning: Bool) {
        guard let item = resolvedItem else {
            onSelect()
            return
        }
        if item.type == .movie || item.type == .episode || item.type == .series || item.type == .boxSet || item.type == .video || item.type == .trailer {
            playbackManager?.play(
                item: item,
                fromBeginning: fromBeginning,
                client: serverViewModel?.client,
                userID: serverViewModel?.currentUser?.id
            )
        } else {
            onSelect()
        }
    }

    private func handleToggleFavorite() {
        guard let serverViewModel, let itemID = resolvedItem?.id ?? itemID else { return }
        let currentFavorite = isFavorite
        let newFavorite = !currentFavorite
        isFavoriteOverride = newFavorite
        Task {
            let result = await serverViewModel.setFavorite(newFavorite, forItemID: itemID)
            if result == nil {
                isFavoriteOverride = currentFavorite
            }
        }
    }

    private func handleResetProgress() {
        guard let item = resolvedItem else { return }
        Task {
            _ = await serverViewModel?.resetProgress(for: item)
            onResetProgress?()
        }
    }

    var body: some View {
        if isRedacted {
            posterImage
                .aspectRatio(effectiveAspectRatio, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else if let item = resolvedItem {
            let state = computeWatchState(for: item)
            cardButton(item: item, isWatched: state.isWatched, isWatching: state.isWatching, watchProgress: state.watchProgress)
        } else {
            posterImage
                .aspectRatio(effectiveAspectRatio, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    @ViewBuilder
    private func cardButton(item: BaseItemDto, isWatched: Bool, isWatching: Bool, watchProgress: Double?) -> some View {
        let resolvedPosterURL = posterURL ?? serverViewModel?.client.flatMap { item.posterURL(client: $0) }

        let baseButton = Button(action: onSelect) {
            posterImageView(url: resolvedPosterURL)
                .aspectRatio(effectiveAspectRatio, contentMode: .fit)
                .overlay(alignment: .bottomTrailing) {
                    VStack(alignment: .trailing, spacing: 6) {
                        if AppPreferences.shared.showProgressBar, let progress = watchProgress, !isWatched && isWatching && Int(progress * 100) > 0 {
                            ProgressBar(progress: progress, barWidth: 40)
                                .transition(.scale(scale: 0.8).combined(with: .opacity))
                        }
                        if let episodeTitle = item.formattedEpisodeNumber {
                            EpisodeBadge(text: episodeTitle)
                        }
                    }
                    .padding(8)
                }
                .overlay(alignment: .topTrailing) {
                    if isWatched {
                        CheckmarkBadge()
                            .padding(8)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contextMenu {
            PlaybackMenuContent(
                title: item.contextMenuTitle(),
                isInProgress: isWatching,
                isWatched: isWatched,
                isFavorite: isFavorite,
                onContinueWatching: {
                    if let onContinueWatching {
                        onContinueWatching()
                    } else {
                        playAction(fromBeginning: false)
                    }
                },
                onStartFromBeginning: {
                    if let onStartFromBeginning {
                        onStartFromBeginning()
                    } else {
                        playAction(fromBeginning: true)
                    }
                },
                onStart: {
                    if let onStartFromBeginning {
                        onStartFromBeginning()
                    } else {
                        playAction(fromBeginning: false)
                    }
                },
                onResetProgress: {
                    handleResetProgress()
                },
                onToggleFavorite: {
                    handleToggleFavorite()
                }
            )
        }
        .scaleEffect(isHovered ? 1.04 : 1.0)
        .brightness(isHovered ? 0.06 : 0)
        #if os(macOS)
        .animation(.easeInOut(duration: 0.2), value: isHovered)
        .onHover { isHovered = $0 }
        #endif

        if let namespace {
            baseButton
                .matchedTransitionSource(id: zoomID ?? item.zoomTransitionID(), in: namespace)
        } else {
            baseButton
        }
    }

    @ViewBuilder
    private var posterImage: some View {
        posterImageView(url: posterURL)
    }

    @ViewBuilder
    private func posterImageView(url: URL?) -> some View {
        ZStack {
            if isRedacted {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.mainOpp.opacity(0.08))
            } else {
                placeholder

                if let url {
                    WebImage(url: url) { phase in
                        if let image = phase.image {
                            image
                                .resizable()
                                .scaledToFill()
                        }
                    }
                    .cancelOnDisappear(true)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color.mainOpp.opacity(0.06))
    }
}
