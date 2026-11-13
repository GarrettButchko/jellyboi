//
//  MediaDetailInfoChips.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 8/23/26.
//

import SwiftUI
import BaseColors
import JellyfinAPI

extension MediaDetailView {

    struct InfoChipItem {
        let icon: String?
        let emoji: String?
        let text: String

        init(icon: String? = nil, emoji: String? = nil, text: String) {
            self.icon = icon
            self.emoji = emoji
            self.text = text
        }
    }

    // MARK: - Skeleton Default Items

    private static let defaultInfoChip = InfoChipItem(icon: "star.fill", text: "8.5")

    private static let defaultInfoChips: [InfoChipItem] = [
        defaultInfoChip,
        InfoChipItem(text: "2024"),
        InfoChipItem(icon: "clock", text: "2h 15m"),
        InfoChipItem(text: "4K UHD"),
        InfoChipItem(icon: "speaker.wave.2", text: "Dolby Atmos")
    ]

    var infoChipData: [InfoChipItem] {
        var chips: [InfoChipItem] = []

        if displayItem.type == .boxSet {
            let count = displayItem.childCount ?? (detailVM.collectionItems.isEmpty ? nil : detailVM.collectionItems.count)
            if let count {
                chips.append(.init(icon: "film.stack", text: "\(count) \(count == 1 ? "Item" : "Items")"))
            }
        }
        if let year = displayItem.productionYear {
            chips.append(.init(icon: "calendar", text: "\(year)"))
        }
        if let runtime = displayItem.formattedRuntime {
            chips.append(.init(icon: "clock", text: runtime))
        }
        if let critic = displayItem.criticRating {
            chips.append(.init(emoji: "🍅", text: "\(Int(critic))%"))
        }
        if let rating = displayItem.officialRating {
            chips.append(.init(text: rating))
        }
        if let community = displayItem.communityRating {
            chips.append(.init(icon: "star.fill", text: String(format: "%.1f", community)))
        }

        return chips
    }

    @ViewBuilder
    var infoChipsScrollView: some View {
        let chips = infoChipData
        ZStack(alignment: .topLeading) {
            if !chips.isEmpty {
                content(chips: chips)
                    .transition(.skeleton)
            } else if detailVM.primaryDetailsStatus.isLoading {
                skeleton
                    .transition(.skeleton)
            }
        }
        .animation(.skeleton, value: chips.isEmpty)
        .animation(.skeleton, value: detailVM.primaryDetailsStatus)
    }

    @ViewBuilder
    func content(chips: [InfoChipItem]) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(chips.indices, id: \.self) { index in
                    InfoCapsule(
                        icon: chips[index].icon,
                        emoji: chips[index].emoji,
                        text: chips[index].text
                    )
                }
            }
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    var skeleton: some View {
        content(chips: Self.defaultInfoChips)
            .skeleton()
    }
}

// MARK: - InfoCapsule

struct InfoCapsule: View {
    let icon: String?
    let emoji: String?
    let text: String

    init(icon: String? = nil, emoji: String? = nil, text: String) {
        self.icon = icon
        self.emoji = emoji
        self.text = text
    }

    var body: some View {
        HStack(spacing: 5) {
            if let emoji {
                Text(emoji)
                    .font(.system(size: 12))
            } else if let icon {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
            }
            Text(text)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .lineLimit(1)
        }
        .foregroundStyle(Color.mainOpp)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.mainOpp.opacity(0.08), in: Capsule())
    }
}
