//
//  AnimatedGradientBackground.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 8/21/26.
//

import SwiftUI

struct AnimatedGradientBackground: View {

    @State private var phase: CGFloat = 0

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            MeshGradientView(t: t)
        }
        .ignoresSafeArea()
    }
}

private struct MeshGradientView: View {

    let t: Double

    var body: some View {
        let angle = t * 0.4
        let s = CGFloat(sin(angle))
        let c = CGFloat(cos(angle))

        let start = UnitPoint(x: 0.5 + 0.5 * c, y: 0.5 + 0.5 * s)
        let end   = UnitPoint(x: 0.5 - 0.5 * c, y: 0.5 - 0.5 * s)

        // pink → purple → teal, matching the Jellyboi logo hues
        let colors: [Color] = [
            Color(red: 0.10, green: 0.65, blue: 0.72),  // teal
            Color(red: 0.80, green: 0.15, blue: 0.72),  // hot pink
            Color(red: 0.44, green: 0.10, blue: 0.75),  // purple
            Color(red: 0.10, green: 0.65, blue: 0.72),  // teal
            Color(red: 0.55, green: 0.08, blue: 0.80),  // violet
            Color(red: 0.10, green: 0.65, blue: 0.72),  // teal
        ]
        let idx = Int(t * 0.25) % colors.count
        let next = (idx + 1) % colors.count
        let blend = CGFloat(t * 0.25 - Double(Int(t * 0.25)))

        return LinearGradient(
            stops: [
                .init(color: colors[idx].mix(with: colors[next], by: blend), location: 0),
                .init(color: colors[(idx + 2) % colors.count]
                    .mix(with: colors[(next + 2) % colors.count], by: blend), location: 1),
            ],
            startPoint: start,
            endPoint: end
        )
    }
}

extension Color {
    func mix(with other: Color, by fraction: CGFloat) -> Color {
        let f = max(0, min(1, fraction))
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        UIColor(self).getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        UIColor(other).getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return Color(
            red:   r1 + (r2 - r1) * f,
            green: g1 + (g2 - g1) * f,
            blue:  b1 + (b2 - b1) * f
        )
    }
}
