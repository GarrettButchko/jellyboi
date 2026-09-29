//
//  MediaDetailButtonRowTopTrailing.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 9/6/26.
//

import SwiftUI
import BaseColors

struct MediaDetailButtonRowTopTrailing: View {
    typealias ButtonItem = (systemName: String, action: () -> Void)

    let isFavorited: Bool
    private let onFavorite: () -> Void
    private let onDownload: () -> Void

    @Namespace private var namespace

    init(
        isFavorited: Bool = false,
        onFavorite: @escaping () -> Void = {},
        onDownload: @escaping () -> Void = {}
    ) {
        self.isFavorited = isFavorited
        self.onFavorite = onFavorite
        self.onDownload = onDownload
    }

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8){
                buttonView(
                    item: (
                        systemName: isFavorited ? "star.fill" : "star",
                        action: onFavorite
                    ),
                    tint: isFavorited ? .yellow : Color.mainOpp
                )
                
                buttonView(
                    item: (systemName: "arrow.down.to.line", action: onDownload),
                    tint: Color.mainOpp
                )
            }
        }
    }

    @ViewBuilder
    private func buttonView(item: ButtonItem, tint: Color) -> some View {
        Button(action: item.action) {
            Image(systemName: item.systemName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tint)
                .contentTransition(.symbolEffect(.replace))
                .padding(11) // smaller than BackButton because the default rounded-rect glass hugs content tighter than a Circle
        }
        .glassEffect(.regular.interactive())
        .glassEffectUnion(id: "trailingButtons", namespace: namespace)
    }
}
