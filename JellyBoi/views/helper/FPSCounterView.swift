//
//  FPSCounterView.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 10/29/26.
//

#if DEBUG
import SwiftUI
import QuartzCore

@MainActor
@Observable
public final class FPSMonitor {
    public static let shared = FPSMonitor()

    public private(set) var currentFPS: Int = 0
    public private(set) var minFPS: Int = 120
    public private(set) var maxFPS: Int = 0
    public private(set) var frameTimeMs: Double = 0.0

    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    private var frameCount: Int = 0
    private var accumulatedTime: CFTimeInterval = 0

    public func start() {
        guard displayLink == nil else { return }
        lastTimestamp = 0
        frameCount = 0
        accumulatedTime = 0
        minFPS = 120
        maxFPS = 0

        let link = CADisplayLink(target: DisplayLinkTarget { [weak self] timestamp, targetTimestamp in
            self?.tick(timestamp: timestamp, targetTimestamp: targetTimestamp)
        }, selector: #selector(DisplayLinkTarget.onTick(link:)))

        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.displayLink = link
    }

    public func stop() {
        displayLink?.invalidate()
        displayLink = nil
        lastTimestamp = 0
    }

    public func resetMinMax() {
        minFPS = currentFPS > 0 ? currentFPS : 120
        maxFPS = currentFPS
    }

    private func tick(timestamp: CFTimeInterval, targetTimestamp: CFTimeInterval) {
        if lastTimestamp == 0 {
            lastTimestamp = timestamp
            return
        }

        let delta = timestamp - lastTimestamp
        lastTimestamp = timestamp

        frameCount += 1
        accumulatedTime += delta

        // Update stats every 0.35s for smooth, readable metrics
        if accumulatedTime >= 0.35 {
            let calculatedFPS = Int(round(Double(frameCount) / accumulatedTime))
            currentFPS = calculatedFPS
            frameTimeMs = (accumulatedTime / Double(frameCount)) * 1000.0

            if calculatedFPS > 0 {
                if calculatedFPS < minFPS {
                    minFPS = calculatedFPS
                }
                if calculatedFPS > maxFPS {
                    maxFPS = calculatedFPS
                }
            }

            frameCount = 0
            accumulatedTime = 0
        }
    }
}

private final class DisplayLinkTarget: NSObject {
    private let action: (CFTimeInterval, CFTimeInterval) -> Void

    init(action: @escaping (CFTimeInterval, CFTimeInterval) -> Void) {
        self.action = action
        super.init()
    }

    @objc func onTick(link: CADisplayLink) {
        action(link.timestamp, link.targetTimestamp)
    }
}

public struct FPSOverlayView: View {
    @State private var monitor = FPSMonitor.shared
    @State private var dragOffset: CGSize = .zero
    @State private var position: CGPoint = CGPoint(x: 100, y: 70)

    public init() {}

    public var body: some View {
        HStack(spacing: 8) {
            // FPS badge
            HStack(spacing: 4) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)

                Text("\(monitor.currentFPS)")
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)

                Text("FPS")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
            }

            Divider()
                .frame(height: 12)
                .background(Color.white.opacity(0.3))

            // Min/Max/Avg badge
            HStack(spacing: 6) {
                Text("min:\(monitor.minFPS)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.75))

                Text("max:\(monitor.maxFPS)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.75))

                Text("\(String(format: "%.1f", monitor.frameTimeMs))ms")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.75))
                .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
        )
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
        )
        .position(x: position.x + dragOffset.width, y: position.y + dragOffset.height)
        .gesture(
            DragGesture()
                .onChanged { value in
                    dragOffset = value.translation
                }
                .onEnded { value in
                    position.x += value.translation.width
                    position.y += value.translation.height
                    dragOffset = .zero
                }
        )
        .onTapGesture(count: 2) {
            monitor.resetMinMax()
        }
        .onAppear {
            monitor.start()
        }
    }

    private var statusColor: Color {
        if monitor.currentFPS >= 100 {
            return .green
        } else if monitor.currentFPS >= 60 {
            return .yellow
        } else {
            return .red
        }
    }
}
#endif
