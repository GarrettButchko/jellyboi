//
//  MediaDetailButtonRow.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 8/23/26.
//

import SwiftUI
import BaseColors

extension MediaDetailView {

    var buttonRow: some View {
        HStack(spacing: 12) {
            //HStack(spacing: 12) {
                Button {
                    // Placeholder — wired when media player screen is added
                } label: {
                    PlayProgressPill(item: displayItem)
                }
                .buttonStyle(.plain)
                
                Button {
                    showOptionsSheet = true
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.mainOpp)
                        .frame(width: 50, height: 50)
                        .glassEffect(.regular.interactive(), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
            //}
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}
