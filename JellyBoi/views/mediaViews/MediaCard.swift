//
//  MediaCard.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 8/25/26.
//

import SwiftUI
import BaseColors
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

    var body: some View {
        Button(action: onSelect) {
            posterImage
                .aspectRatio(viewModel.cardAspectRatio(overrideRatio: imageAspectRatio), contentMode: .fit)
                .overlay(alignment: .bottomTrailing) {
                    VStack(alignment: .trailing, spacing: 6) {
                        if let progress = viewModel.watchProgress, !viewModel.isWatched && viewModel.isWatching {
                            GlassProgressBar(progress: progress, barWidth: 40)
                        }
                        if let episodeTitle = viewModel.episodeTitle {
                            episodeBadge(text: episodeTitle)
                        }
                    }
                    .padding(8)
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
                        viewModel.handleContinueWatching(onSelect: onSelect, onContinueWatching: onContinueWatching)
                    } label: {
                        Label("Continue watching", systemImage: "play.fill")
                    }

                    Button {
                        viewModel.handleStartFromBeginning(onSelect: onSelect, onStartFromBeginning: onStartFromBeginning)
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
                        viewModel.handleStartFromBeginning(onSelect: onSelect, onStartFromBeginning: onStartFromBeginning)
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
                        viewModel.handleStart(onSelect: onSelect, onStartFromBeginning: onStartFromBeginning)
                    } label: {
                        Label("Start", systemImage: "play.fill")
                    }
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
    }

    private func episodeBadge(text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.mainOpp)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .glassEffect(.clear.tint(Color.main.opacity(0.6)), in: Capsule())
    }

    @ViewBuilder
    private var posterImage: some View {
        if let url = posterURL {
            WebImage(
                url: url,
                transaction: Transaction(animation: .easeInOut(duration: 0.3))
            ) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .scaledToFill()
                        .transition(.fade(duration: 0.3))
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
