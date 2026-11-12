//
//  MediaDetailButtonRowTopTrailing.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 9/6/26.
//

import SwiftUI
import BaseColors
import JellyfinAPI

// MARK: - Back & Trailing Buttons View

extension MediaDetailView {

    // MARK: - Top Navigation Bar

    var topNavigationBar: some View {
        HStack(spacing: 8) {
            BackButton()
            if detailVM.shouldShowSeriesButton(cameFromShow: cameFromShow) {
                Button {
                    if let series = detailVM.parentSeries(libraryViewModel: libraryViewModel) {
                        selectedSeries = series
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .padding(14)
                        .hidden()
                        .overlay {
                            Image(systemName: "tv")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Color.mainOpp)
                        }
                }
                .glassEffect(.regular.interactive(), in: Circle())
                .accessibilityLabel("Go to Show")
            }
            Spacer()
            topTrailingButtons
        }
        .padding(.horizontal, 16)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: {
            backButtonHeight = $0
        }
    }

    // MARK: - Top Trailing Buttons

    var topTrailingButtons: some View {
        MediaDetailTopTrailingButtons(
            detailVM: detailVM,
            item: item
        )
    }
}

// MARK: - MediaDetailTopTrailingButtons

struct MediaDetailTopTrailingButtons: View {
    @Bindable var detailVM: MediaDetailViewModel
    let item: BaseItemDto

    @Environment(ServerViewModel.self) private var serverViewModel
    @Namespace private var trailingButtonsNamespace

    var body: some View {
        let isFavorited = detailVM.isFavorite(fallback: item)

        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    Task {
                        await detailVM.toggleFavorite(serverViewModel: serverViewModel, fallbackItem: item)
                    }
                } label: {
                    Image(systemName: isFavorited ? "star.fill" : "star")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(isFavorited ? .yellow : Color.mainOpp)
                        .contentTransition(.symbolEffect(.replace))
                        .padding(11)
                }
                .glassEffect(.regular.interactive())
                .glassEffectUnion(id: "trailingButtons", namespace: trailingButtonsNamespace)

                MediaDetailDownloadButton(
                    detailVM: detailVM,
                    item: item,
                    trailingButtonsNamespace: trailingButtonsNamespace
                )
            }
        }
    }
}

// MARK: - MediaDetailDownloadButton

/// Isolated download button subview that observes `DownloadManager` independently,
/// preventing download progress updates from invalidating the entire `MediaDetailView` hierarchy.
struct MediaDetailDownloadButton: View {
    @Bindable var detailVM: MediaDetailViewModel
    let item: BaseItemDto
    var trailingButtonsNamespace: Namespace.ID

    @Environment(DownloadManager.self) private var downloadManager
    @Environment(ServerViewModel.self) private var serverViewModel
    @Environment(LibraryViewModel.self) private var libraryViewModel
    @Environment(AppPreferences.self) private var preferences: AppPreferences?

    var body: some View {
        let isDownloading = detailVM.isDetailDownloading(downloadManager: downloadManager)
        let isDownloaded = detailVM.isDetailDownloaded(downloadManager: downloadManager, libraryViewModel: libraryViewModel)
        let downloadProgress = detailVM.detailDownloadProgress(downloadManager: downloadManager, libraryViewModel: libraryViewModel)
        let accent = Color.appAccent

        Button {
            detailVM.handleDownloadTap(
                downloadManager: downloadManager,
                client: serverViewModel.client,
                libraryViewModel: libraryViewModel
            )
        } label: {
            if isDownloading {
                ZStack {
                    Circle()
                        .stroke(Color.mainOpp.opacity(0.15), lineWidth: 2.5)
                        .frame(width: 22, height: 22)

                    Circle()
                        .trim(from: 0, to: max(0.04, CGFloat(downloadProgress)))
                        .stroke(accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 22, height: 22)
                        .animation(.smooth(duration: 0.2), value: downloadProgress)

                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(Color.mainOpp)
                        .frame(width: 7.5, height: 7.5)
                }
                .frame(width: 39, height: 39)
                .contentShape(Circle())
            } else {
                if isDownloaded {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.white, accent)
                        .contentTransition(.symbolEffect(.replace))
                        .padding(11)
                } else {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.mainOpp)
                        .contentTransition(.symbolEffect(.replace))
                        .padding(11)
                }
            }
        }
        .glassEffect(.regular.interactive())
        .glassEffectUnion(id: "trailingButtons", namespace: trailingButtonsNamespace)
        .accessibilityLabel(isDownloading ? "Stop Download" : (isDownloaded ? "Delete Download" : "Download"))
    }
}
