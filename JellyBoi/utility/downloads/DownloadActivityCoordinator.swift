//
//  DownloadActivityCoordinator.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 10/20/26.
//

import Foundation
import ActivityKit

@MainActor
public final class DownloadActivityCoordinator {
    public static let shared = DownloadActivityCoordinator()

    private var currentActivity: Activity<DownloadActivityAttributes>?
    private var lastUpdateTime: Date = .distantPast
    private var lastProgress: Double = -1.0
    private var lastTitle: String = ""

    private init() {
        if let existing = Activity<DownloadActivityAttributes>.activities.first {
            self.currentActivity = existing
        }
    }

    public var areActivitiesEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    public func update(
        presentation: DownloadSummaryPresentation,
        force: Bool = false
    ) {
        guard areActivitiesEnabled else { return }

        let now = Date()
        _ = abs(presentation.progress - lastProgress)
        let titleChanged = presentation.title != lastTitle
        let timeSinceLast = now.timeIntervalSince(lastUpdateTime)

        if !force && !titleChanged && timeSinceLast < 1.5 {
            return
        }

        lastUpdateTime = now
        lastProgress = presentation.progress
        lastTitle = presentation.title

        let state = DownloadActivityAttributes.ContentState(
            title: presentation.title,
            subtitle: presentation.subtitle,
            detailText: presentation.detailText,
            progress: presentation.progress,
            itemsRemaining: presentation.itemsRemaining,
            totalItems: presentation.totalItems,
            isCompleted: presentation.isCompleted
        )

        let content = ActivityContent(state: state, staleDate: nil)

        if let activity = currentActivity ?? Activity<DownloadActivityAttributes>.activities.first {
            currentActivity = activity
            Task {
                await activity.update(content)
            }
        } else if !presentation.isCompleted && presentation.itemsRemaining > 0 {
            do {
                let attributes = DownloadActivityAttributes()
                let activity = try Activity.request(
                    attributes: attributes,
                    content: content,
                    pushType: nil
                )
                self.currentActivity = activity
            } catch {
                print("[DownloadActivityCoordinator] Failed to start Live Activity: \(error.localizedDescription)")
            }
        }
    }

    public func finishAll(finalTitle: String = "Downloads Complete") {
        guard let activity = currentActivity ?? Activity<DownloadActivityAttributes>.activities.first else {
            return
        }

        let finalState = DownloadActivityAttributes.ContentState(
            title: finalTitle,
            subtitle: "All items ready offline",
            detailText: "100%",
            progress: 1.0,
            itemsRemaining: 0,
            totalItems: 0,
            isCompleted: true
        )

        let finalContent = ActivityContent(state: finalState, staleDate: nil)

        Task {
            await activity.end(finalContent, dismissalPolicy: .after(Date().addingTimeInterval(4.0)))
            self.currentActivity = nil
            self.lastProgress = -1.0
            self.lastTitle = ""
        }
    }

    public func cancel() {
        let activities = Activity<DownloadActivityAttributes>.activities
        for activity in activities {
            Task {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
        currentActivity = nil
        lastProgress = -1.0
        lastTitle = ""
    }
}
