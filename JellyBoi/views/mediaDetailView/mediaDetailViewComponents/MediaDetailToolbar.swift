//
//  MediaDetailToolbar.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 9/6/26.
//

import SwiftUI
import BaseColors
import JellyfinAPI

// MARK: - MediaDetailView Toolbar

extension MediaDetailView {

    /// Navigation bar contents for the detail screen.
    ///
    /// The system supplies the glass background for toolbar items, so nothing here
    /// applies `glassEffect` of its own.
    @ToolbarContentBuilder
    var mediaDetailToolbar: some ToolbarContent {
        if detailVM.shouldShowSeriesButton {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    if let series = detailVM.parentSeries {
                        selectedSeries = series
                    }
                } label: {
                    Image(systemName: "tv")
                }
                .accessibilityLabel("Go to Show")
            }
        }
        
        ToolbarItem(id: "detail-favorite", placement: .topBarTrailing) {
            MediaDetailFavoriteButton(detailVM: detailVM)
            MediaDetailDownloadButton(detailVM: detailVM)
        }
    }
}

// MARK: - MediaDetailFavoriteButton

struct MediaDetailFavoriteButton: View {
    let detailVM: MediaDetailViewModel

    var body: some View {
        let isFavorited = detailVM.isFavorite

        Button {
            detailVM.toggleFavorite()
        } label: {
            Image(systemName: isFavorited ? "star.fill" : "star")
                .foregroundStyle(isFavorited ? Color.yellow : Color.primary)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 22, height: 22)
        }
        .accessibilityLabel(isFavorited ? "Remove from Favorites" : "Add to Favorites")
    }
}

// MARK: - MediaDetailDownloadButton

/// Isolated download button subview that observes `DownloadManager` independently,
/// preventing download progress updates from invalidating the entire `MediaDetailView` hierarchy.
struct MediaDetailDownloadButton: View {
    let detailVM: MediaDetailViewModel

    var body: some View {
        let isDownloading = detailVM.isDetailDownloading
        let isDownloaded = detailVM.isDetailDownloaded
        let downloadProgress = detailVM.detailDownloadProgress
        let accent = Color.appAccent

        Button {
            detailVM.handleDownloadTap()
        } label: {
            if isDownloading {
                ZStack {
                    Circle()
                        .stroke(Color.primary.opacity(0.15), lineWidth: 2.5)

                    Circle()
                        .trim(from: 0, to: max(0.04, CGFloat(downloadProgress)))
                        .stroke(accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.smooth(duration: 0.2), value: downloadProgress)

                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(Color.primary)
                        .frame(width: 6, height: 6)
                }
                .frame(width: 20, height: 20)
                .frame(width: 22, height: 22)
            } else if isDownloaded {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(accent)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 22, height: 22)
            } else {
                Image(systemName: "arrow.down")
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 22, height: 22)
            }
        }
        .accessibilityLabel(isDownloading ? "Stop Download" : (isDownloaded ? "Delete Download" : "Download"))
    }
}
