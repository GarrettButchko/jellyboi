//
//  MediaDetailExtraInfoSection.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 8/23/26.
//

import SwiftUI
import BaseColors
import JellyfinAPI

extension MediaDetailView {

    @ViewBuilder
    var extraInfoSection: some View {
        if detailVM.hasExtraInfo {
            extraInfoContent
                .padding(.horizontal, 20)
        }
    }

    private var extraInfoContent: some View {
        let people = displayItem.people ?? []
        let directors = people.filter { $0.type == .director }.compactMap(\.name)
        let writers   = people.filter { $0.type == .writer   }.compactMap(\.name)

        return VStack(alignment: .leading, spacing: 16) {
            Text("Extra Info")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Color.mainOpp)

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

struct ExtraInfoRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(Color.mainOpp.opacity(0.45))
            Text(value)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(Color.mainOpp)
        }
    }
}
