//
//  MediaDetailExtraInfoSection.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 8/23/26.
//

import SwiftUI
import BaseColors
import JellyfinAPI

// MARK: - Skeleton Default Items

private struct DefaultExtraInfoRow {
    let label: String
    let value: String
}

private let defaultExtraInfoRows: [DefaultExtraInfoRow] = [
    DefaultExtraInfoRow(label: "Genres", value: "Action, Adventure, Science Fiction"),
    DefaultExtraInfoRow(label: "Director", value: "Director Name"),
    DefaultExtraInfoRow(label: "Writers", value: "Writer Name"),
    DefaultExtraInfoRow(label: "Studios", value: "Studio Name")
]

extension MediaDetailView {

    /// Shown while the screen is still loading and the item has no extra info yet, so the section
    /// fades in with the rest of the details instead of popping into existence.
    private var isExtraInfoPlaceholderVisible: Bool {
        !detailVM.hasExtraInfo && (detailVM.isLoading || detailVM.primaryDetailsStatus.isLoading)
    }

    @ViewBuilder
    var extraInfoSection: some View {
        if detailVM.hasExtraInfo || isExtraInfoPlaceholderVisible {
            Group {
                if detailVM.hasExtraInfo {
                    extraInfoContent
                } else {
                    extraInfoSkeleton
                }
            }
            .padding(.horizontal, 20)
            .skeleton(when: isExtraInfoPlaceholderVisible, value: detailVM.hasExtraInfo)
        }
    }

    private var extraInfoTitle: some View {
        Text("Extra Info")
            .font(.system(size: 20, weight: .bold))
            .foregroundStyle(Color.mainOpp)
    }

    private var extraInfoSkeleton: some View {
        VStack(alignment: .leading, spacing: 12) {
            extraInfoTitle

            ForEach(defaultExtraInfoRows, id: \.label) { row in
                ExtraInfoRow(label: row.label, value: row.value)
            }
        }
    }

    private var extraInfoContent: some View {
        let people = displayItem.people ?? []
        let directors = people.filter { $0.type == .director }.compactMap(\.name)
        let writers   = people.filter { $0.type == .writer   }.compactMap(\.name)

        return VStack(alignment: .leading, spacing: 12) {
            extraInfoTitle

            if let genres = displayItem.genres, !genres.isEmpty {
                ExtraInfoRow(label: "Genres", value: genres.joined(separator: ", "))
            }
            if !directors.isEmpty {
                ExtraInfoRow(label: "Director", value: directors.joined(separator: ", "))
            }
            if !writers.isEmpty {
                ExtraInfoRow(label: "Writers", value: writers.joined(separator: ", "))
            }
            if let studios = displayItem.studios {
                let names = studios.compactMap(\.name)
                if !names.isEmpty {
                    ExtraInfoRow(label: "Studios", value: names.joined(separator: ", "))
                }
            }
        }
    }
}

// MARK: - ExtraInfoRow

private struct ExtraInfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(Color.mainOpp.opacity(0.55))
                .frame(width: 80, alignment: .leading)

            ScrollView(.horizontal) {
                HStack{
                    Text(value)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.mainOpp)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}
