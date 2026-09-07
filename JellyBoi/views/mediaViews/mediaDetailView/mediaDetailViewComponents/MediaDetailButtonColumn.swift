//
//  MediaDetailButtonRow.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 8/23/26.
//

import SwiftUI
import BaseColors

extension MediaDetailView {

    var buttonColumn: some View {
        VStack(spacing: 12) {
            PlayProgressPill(item: displayItem, onOptions: { showOptionsSheet = true })
        }
    }
}
