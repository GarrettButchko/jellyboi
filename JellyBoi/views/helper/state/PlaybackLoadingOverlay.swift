//
//  PlaybackLoadingOverlay.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 11/13/26.
//

import SwiftUI
import BaseColors

/// Dimmed loading card shown while playback is being prepared, with an option to abort.
struct PlaybackLoadingOverlay: View {
    let message: String
    let onStop: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
            VStack{
                Spacer()
                
                VStack(spacing: 20) {
                    JellyBoiLoadingIndicator()
                    
                    Text(message)
                        .font(.system(.subheadline, weight: .medium))
                        .foregroundStyle(.secondary)
                    
                    
                }
                .padding(28)
                .background {
                    RoundedRectangle(cornerRadius: 38, style: .continuous)
                        .playbackGlassCard()
                }
                
                Spacer()
                
                Text("Tap Anywhere to Cancel")
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.5))
                    .padding(.bottom, 70)
                    .shadow(radius: 50)
            }
            .padding(.horizontal, 30)
            .transition(.scale(scale: 0.9).combined(with: .opacity))
            
        }
        .onTapGesture(perform: onStop)
    }
}

// MARK: - Glass Card Background

private extension Shape {
    @ViewBuilder
    func playbackGlassCard() -> some View {
        if #available(iOS 26.0, *) {
            self
                .fill(.regularMaterial)
                .glassEffect(.clear, in: self)
                .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
        } else {
            self
                .fill(.ultraThinMaterial)
                .clipShape(self)
                .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
        }
    }
}
