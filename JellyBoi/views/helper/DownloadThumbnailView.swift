//
//  DownloadThumbnailView.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 10/23/26.
//

import SwiftUI
import BaseColors
import JellyfinAPI
import SDWebImageSwiftUI

enum DownloadThumbnailSize: Equatable {
    case compact // Floating bar: 44x28 (episode) or 20x28 (poster)
    case regular // Sheet / list: 86x54 (episode) or 38x54 (poster)

    var height: CGFloat {
        switch self {
        case .compact: return 28
        case .regular: return 54
        }
    }

    func width(isEpisode: Bool) -> CGFloat {
        switch self {
        case .compact: return isEpisode ? 44 : 20
        case .regular: return isEpisode ? 86 : 38
        }
    }

    var cornerRadius: CGFloat {
        switch self {
        case .compact: return 6
        case .regular: return 14
        }
    }

    var logoSize: CGFloat {
        switch self {
        case .compact: return 14
        case .regular: return 26
        }
    }
}

struct DownloadThumbnailView: View, Equatable {
    let imageURL: URL?
    let isEpisode: Bool
    var isShow: Bool
    var size: DownloadThumbnailSize

    init(
        imageURL: URL?,
        isEpisode: Bool,
        isShow: Bool = false,
        size: DownloadThumbnailSize = .regular
    ) {
        self.imageURL = imageURL
        self.isEpisode = isEpisode
        self.isShow = isShow
        self.size = size
    }

    init(
        item: DownloadItem,
        client: JellyfinClient?,
        libraryViewModel: LibraryViewModel? = nil,
        size: DownloadThumbnailSize = .regular
    ) {
        let isEp = item.item.type == .episode
        let url = item.artworkURL(client: client, libraryViewModel: libraryViewModel)
        self.init(
            imageURL: url,
            isEpisode: isEp,
            isShow: item.group?.type == .show,
            size: size
        )
    }

    init(
        group: ShowDownloadGroup,
        client: JellyfinClient?,
        libraryViewModel: LibraryViewModel? = nil,
        size: DownloadThumbnailSize = .regular
    ) {
        let url = group.posterURL(client: client, libraryViewModel: libraryViewModel)
        self.init(
            imageURL: url,
            isEpisode: false,
            isShow: group.groupInfo?.type != .collection,
            size: size
        )
    }

    private var placeholder: some View {
        Color.subTwo
            .overlay {
                Image("Jellyboi")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size.logoSize, height: size.logoSize)
                    .foregroundStyle(Color.mainOpp.opacity(0.10))
                    .rotationEffect(.degrees(45))
            }
    }

    var body: some View {
        ZStack {
            Color.subTwo

            if let imageURL {
                WebImage(url: imageURL) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    placeholder
                }
            } else {
                placeholder
            }
        }
        .frame(width: size.width(isEpisode: isEpisode), height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: size.cornerRadius, style: .continuous))
    }

    static func == (lhs: DownloadThumbnailView, rhs: DownloadThumbnailView) -> Bool {
        lhs.imageURL == rhs.imageURL &&
        lhs.isEpisode == rhs.isEpisode &&
        lhs.isShow == rhs.isShow &&
        lhs.size == rhs.size
    }
}
