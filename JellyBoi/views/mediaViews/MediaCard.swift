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

struct MediaCard: View {
    let item: BaseItemDto
    let posterURL: URL?
    let namespace: Namespace.ID
    let onSelect: () -> Void
    var zoomID: AnyHashable? = nil
    var imageAspectRatio: CGFloat? = nil
    var onContinueWatching: (() -> Void)? = nil
    var onStartFromBeginning: (() -> Void)? = nil
    var onResetProgress: (() -> Void)? = nil

    @Environment(ServerViewModel.self) private var serverViewModel: ServerViewModel?
    @Environment(LibraryViewModel.self) private var libraryViewModel: LibraryViewModel?
    @Environment(PlaybackManager.self) private var playbackManager: PlaybackManager?

    @State private var viewModel: MediaCardViewModel

    init(
        item: BaseItemDto,
        posterURL: URL?,
        namespace: Namespace.ID,
        onSelect: @escaping () -> Void,
        zoomID: AnyHashable? = nil,
        imageAspectRatio: CGFloat? = nil,
        onContinueWatching: (() -> Void)? = nil,
        onStartFromBeginning: (() -> Void)? = nil,
        onResetProgress: (() -> Void)? = nil
    ) {
        self.item = item
        self.posterURL = posterURL
        self.namespace = namespace
        self.onSelect = onSelect
        self.zoomID = zoomID
        self.imageAspectRatio = imageAspectRatio
        self.onContinueWatching = onContinueWatching
        self.onStartFromBeginning = onStartFromBeginning
        self.onResetProgress = onResetProgress
        _viewModel = State(initialValue: MediaCardViewModel(item: item))
    }

    private func playAction(fromBeginning: Bool) {
        if item.type == .movie || item.type == .episode || item.type == .series || item.type == .boxSet {
            playbackManager?.play(
                item: item,
                fromBeginning: fromBeginning,
                client: serverViewModel?.client,
                userID: serverViewModel?.currentUser?.id,
                libraryViewModel: libraryViewModel
            )
        } else {
            onSelect()
        }
    }

    var body: some View {
        Button(action: onSelect) {
            posterImage
                .aspectRatio(viewModel.cardAspectRatio(overrideRatio: imageAspectRatio), contentMode: .fit)
                .overlay(alignment: .bottomTrailing) {
                    VStack(alignment: .trailing, spacing: 6) {
                        if let progress = viewModel.watchProgress, !viewModel.isWatched && viewModel.isWatching && Int(progress * 100) > 0 {
                            GlassProgressBar(progress: progress, barWidth: 40)
                                .transition(.scale(scale: 0.8).combined(with: .opacity))
                        }
                        if let episodeTitle = viewModel.episodeTitle {
                            episodeBadge(text: episodeTitle)
                        }
                    }
                    .padding(8)
                    .animation(.smooth(duration: 0.3), value: viewModel.isWatching)
                }
                .overlay(alignment: .topTrailing) {
                    if viewModel.isWatched {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.mainOpp)
                            .padding(6)
                            .glassEffect(.clear.tint(Color.main.opacity(0.8)), in: Circle())
                            .padding(8)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contextMenu {
            Section {
                if viewModel.isInProgress(in: libraryViewModel) {
                    Button {
                        if let onContinueWatching {
                            onContinueWatching()
                        } else {
                            playAction(fromBeginning: false)
                        }
                    } label: {
                        Label("Continue watching", systemImage: "play.fill")
                    }

                    Button {
                        if let onStartFromBeginning {
                            onStartFromBeginning()
                        } else {
                            playAction(fromBeginning: true)
                        }
                    } label: {
                        Label("Start from beginning", systemImage: "arrow.counterclockwise")
                    }

                    Button(role: .destructive) {
                        viewModel.handleResetProgress(
                            serverViewModel: serverViewModel,
                            onResetProgress: onResetProgress
                        )
                    } label: {
                        Label("Reset Progress", systemImage: "xmark.circle")
                    }
                } else if viewModel.isWatched {
                    Button {
                        if let onStartFromBeginning {
                            onStartFromBeginning()
                        } else {
                            playAction(fromBeginning: true)
                        }
                    } label: {
                        Label("Start from beginning", systemImage: "arrow.counterclockwise")
                    }

                    Button(role: .destructive) {
                        viewModel.handleResetProgress(
                            serverViewModel: serverViewModel,
                            onResetProgress: onResetProgress
                        )
                    } label: {
                        Label("Reset Progress", systemImage: "xmark.circle")
                    }
                } else {
                    Button {
                        if let onStartFromBeginning {
                            onStartFromBeginning()
                        } else {
                            playAction(fromBeginning: false)
                        }
                    } label: {
                        Label("Start", systemImage: "play.fill")
                    }
                }

                Button {
                    viewModel.handleToggleFavorite(serverViewModel: serverViewModel)
                } label: {
                    Label(
                        viewModel.item.isFavorite ? "Unfavorite" : "Favorite",
                        systemImage: viewModel.item.isFavorite ? "star.fill" : "star"
                    )
                }
            } header: {
                if !viewModel.contextMenuTitle.isEmpty {
                    Text(viewModel.contextMenuTitle)
                }
            }
        }
        .scaleEffect(viewModel.isHovered ? 1.04 : 1.0)
        .brightness(viewModel.isHovered ? 0.06 : 0)
        .animation(.easeInOut(duration: 0.2), value: viewModel.isHovered)
        .onHover { viewModel.isHovered = $0 }
        .matchedTransitionSource(id: zoomID ?? AnyHashable(item), in: namespace)
        .onChange(of: item) { _, newItem in
            viewModel.updateItem(newItem)
        }
        .onReceive(NotificationCenter.default.publisher(for: .mediaProgressReset)) { notification in
            if let resetID = notification.object as? String {
                viewModel.handleProgressResetNotification(resetID: resetID)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .mediaProgressUpdated)) { notification in
            if let updatedID = notification.object as? String,
               let ticks = notification.userInfo?["positionTicks"] as? Int {
                let total = notification.userInfo?["durationTicks"] as? Int
                viewModel.handleProgressUpdatedNotification(itemID: updatedID, positionTicks: ticks, totalTicks: total)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .mediaFavoriteToggled)) { notification in
            if let itemID = notification.object as? String,
               let isFavorite = notification.userInfo?["isFavorite"] as? Bool {
                viewModel.handleFavoriteNotification(itemID: itemID, isFavorite: isFavorite)
            }
        }
    }

    private func episodeBadge(text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.mainOpp)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .glassEffect(.clear.tint(Color.main.opacity(0.6)), in: Capsule())
    }

    private var isImageCached: Bool {
        guard let url = posterURL else { return false }
        let key = SDWebImageManager.shared.cacheKey(for: url)
        return SDImageCache.shared.imageFromMemoryCache(forKey: key) != nil
    }

    @ViewBuilder
    private var posterImage: some View {
        if let url = posterURL {
            let isCached = isImageCached
            WebImage(
                url: url,
                transaction: isCached ? Transaction() : Transaction(animation: .easeInOut(duration: 0.25))
            ) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .scaledToFill()
                        .transition(isCached ? .identity : .fade(duration: 0.25))
                } else {
                    placeholder
                }
            }
            .frame(maxWidth: .infinity)
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        Color.sub
            .overlay {
                Image("Jellyboi")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 50, height: 50)
                    .opacity(0.05)
                    .rotationEffect(Angle(degrees: 45))
            }
    }
}
