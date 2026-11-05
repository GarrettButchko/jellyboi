//
//  PlaybackMenuContent.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 9/29/26.
//

import SwiftUI
import BaseColors

struct PlaybackMenuContent: View {
    var title: String? = nil
    var isInProgress: Bool = false
    var isWatched: Bool = false
    var isFavorite: Bool? = nil
    var onContinueWatching: (() -> Void)? = nil
    var onStartFromBeginning: (() -> Void)? = nil
    var onStart: (() -> Void)? = nil
    var onResetProgress: (() -> Void)? = nil
    var onToggleFavorite: (() -> Void)? = nil

    var body: some View {
        Section {
            if isInProgress {
                if let onContinueWatching {
                    Button(action: onContinueWatching) {
                        Label("Continue watching", systemImage: "play.fill")
                            .tint(Color.mainOpp)
                    }
                }

                if let onStartFromBeginning {
                    Button(action: onStartFromBeginning) {
                        Label("Start from beginning", systemImage: "arrow.counterclockwise")
                            .tint(Color.mainOpp)
                    }
                }

                if let onResetProgress {
                    Button(role: .destructive, action: onResetProgress) {
                        Label("Reset Progress", systemImage: "xmark.circle")
                            .tint(Color.red)
                    }
                }
            } else if isWatched {
                if let onStartFromBeginning {
                    Button(action: onStartFromBeginning) {
                        Label("Start from beginning", systemImage: "arrow.counterclockwise")
                            .tint(Color.mainOpp)
                    }
                }

                if let onResetProgress {
                    Button(role: .destructive, action: onResetProgress) {
                        Label("Reset Progress", systemImage: "xmark.circle")
                            .tint(Color.red)
                    }
                }
            } else {
                let startAction = onStart ?? onStartFromBeginning ?? onContinueWatching
                if let startAction {
                    Button(action: startAction) {
                        Label("Start", systemImage: "play.fill")
                            .tint(Color.mainOpp)
                    }
                }
            }

            if let isFavorite, let onToggleFavorite {
                Button(action: onToggleFavorite) {
                    Label(
                        isFavorite ? "Unfavorite" : "Favorite",
                        systemImage: isFavorite ? "star.fill" : "star"
                    )
                    .tint(Color.mainOpp)
                }
            }
        } header: {
            if let title, !title.isEmpty {
                Text(title)
            }
        }
    }
}
