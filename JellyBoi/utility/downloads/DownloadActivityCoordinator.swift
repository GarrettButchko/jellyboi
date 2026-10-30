//
//  DownloadActivityCoordinator.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 10/20/26.
//

import Foundation
import ActivityKit
import UIKit

@MainActor
public final class DownloadActivityCoordinator {
    public static let shared = DownloadActivityCoordinator()

    private var currentActivity: Activity<DownloadActivityAttributes>?
    private var lastUpdateTime: Date = .distantPast
    private var lastProgress: Double = -1.0
    private var lastTitle: String? = nil
    private var lastPosterData: Data? = nil
    private var finishDismissalTask: Task<Void, Never>?

    private init() {
        self.currentActivity = Activity<DownloadActivityAttributes>.activities.first(where: { $0.activityState == .active })
    }

    private var activeActivity: Activity<DownloadActivityAttributes>? {
        if let current = currentActivity, current.activityState == .active {
            return current
        }
        return Activity<DownloadActivityAttributes>.activities.first(where: { $0.activityState == .active })
    }

    public func update(presentation: DownloadSummaryPresentation, force: Bool = false) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        // Cancel any pending dismissal so that a subsequent download continues seamlessly
        finishDismissalTask?.cancel()
        finishDismissalTask = nil

        let now = Date()
        let timeSinceLast = now.timeIntervalSince(lastUpdateTime)
        let progressDiff = abs(presentation.progress - lastProgress)

        let isMajorStateChange = (lastProgress < 0) ||
            presentation.isCompleted ||
            (presentation.title != lastTitle) ||
            (presentation.itemsRemaining == 0)

        // Throttle updates: minimum 1.5s between updates unless progress changed significantly (>= 5%)
        // or a major state transition occurred
        if !force && !isMajorStateChange {
            if timeSinceLast < 1.5 && progressDiff < 0.05 {
                return
            }
        }

        lastUpdateTime = now
        lastProgress = presentation.progress
        lastTitle = presentation.title

        if presentation.isSingleElement {
            if let posterData = presentation.posterImageData {
                lastPosterData = posterData
            }
        } else {
            lastPosterData = nil
        }

        var state = presentation.contentState(fallbackPosterData: lastPosterData)

        // Hard payload size guard: verify encoded ContentState is well below the 4096-byte ActivityKit limit
        if let encoded = try? JSONEncoder().encode(state), encoded.count > 3800 {
            print("[DownloadActivityCoordinator] Warning: ContentState payload (\(encoded.count) bytes) is too large. Stripping poster data.")
            state.posterImageData = nil
            lastPosterData = nil
        }

        let content = ActivityContent(state: state, staleDate: nil)

        if let activity = activeActivity {
            currentActivity = activity
            Task {
                await activity.update(content)
            }
        } else if !presentation.isCompleted && presentation.itemsRemaining > 0 {
            // End any stale or inactive activities before starting a new one
            for stale in Activity<DownloadActivityAttributes>.activities where stale.activityState != .active {
                Task {
                    await stale.end(nil, dismissalPolicy: .immediate)
                }
            }

            do {
                let attributes = DownloadActivityAttributes()
                let activity = try Activity.request(
                    attributes: attributes,
                    content: content,
                    pushType: nil
                )
                self.currentActivity = activity
            } catch {
                print("[DownloadActivityCoordinator] Failed to start Live Activity: \(error)")
                // Fallback: If payload was rejected, retry immediately without poster data so activity ALWAYS shows
                if state.posterImageData != nil {
                    var fallbackState = state
                    fallbackState.posterImageData = nil
                    let fallbackContent = ActivityContent(state: fallbackState, staleDate: nil)
                    do {
                        let activity = try Activity.request(
                            attributes: DownloadActivityAttributes(),
                            content: fallbackContent,
                            pushType: nil
                        )
                        self.currentActivity = activity
                    } catch {
                        print("[DownloadActivityCoordinator] Fallback request failed: \(error)")
                    }
                }
            }
        }
    }

    public func finishAll(finalTitle: String = "Downloads Complete") {
        guard let activity = activeActivity else { return }

        let finalState = DownloadActivityAttributes.ContentState(
            title: finalTitle,
            subtitle: "All items ready offline",
            detailText: "100%",
            progress: 1.0,
            itemsRemaining: 0,
            totalItems: 0,
            status: .completed,
            posterImageData: lastPosterData,
            isSingleElement: lastPosterData != nil
        )

        let content = ActivityContent(state: finalState, staleDate: nil)

        finishDismissalTask?.cancel()
        finishDismissalTask = Task {
            await activity.update(content)
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            await activity.end(content, dismissalPolicy: .default)
            if self.currentActivity?.id == activity.id {
                self.currentActivity = nil
            }
        }
    }

    public func cancel() {
        cancelAll()
    }

    public func cancelAll() {
        finishDismissalTask?.cancel()
        finishDismissalTask = nil
        let activitiesToEnd = Activity<DownloadActivityAttributes>.activities
        currentActivity = nil
        lastProgress = -1.0
        lastTitle = nil
        lastPosterData = nil

        for activity in activitiesToEnd {
            Task {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }
}
