//
//  MediaDetailOptionsSheet.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 8/23/26.
//

import SwiftUI
import BaseColors
import JellyfinAPI

extension MediaDetailView {

    var optionsSheet: some View {
        VStack(spacing: 0) {
            Text(item.name ?? "Options")
                .font(.system(.headline, design: .rounded, weight: .semibold))
                .foregroundStyle(Color.mainOpp)
                .padding(.top, 24)
                .padding(.bottom, 20)

            Divider()
                .foregroundStyle(Color.mainOpp.opacity(0.12))

            VStack(spacing: 0) {
                optionsRow(icon: "play.circle", label: "Play Next") { }
                optionsRow(icon: "plus.circle", label: "Add to Playlist") { }
                optionsRow(icon: "square.and.arrow.up", label: "Share") { }
            }
            .padding(.top, 4)

            Spacer()
        }
        .background(Color.bg)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    func optionsRow(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color.mainOpp.opacity(0.6))
                    .frame(width: 28)
                Text(label)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Color.mainOpp)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }
}
