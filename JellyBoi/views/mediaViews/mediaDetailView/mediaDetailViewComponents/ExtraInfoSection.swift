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
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .top)),
                    removal: .opacity
                ))
                .animation(.skeleton, value: detailVM.hasExtraInfo)
        }
    }

    private var extraInfoContent: some View {
        let people = displayItem.people ?? []
        let directors = people.filter { $0.type == .director }.compactMap(\.name)
        let writers   = people.filter { $0.type == .writer   }.compactMap(\.name)

        return VStack(alignment: .leading, spacing: 12) {
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
