//
//  DownloadNotificationManager.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 10/20/26.
//

import Foundation
import UserNotifications

@MainActor
public final class DownloadNotificationManager {
    public static let shared = DownloadNotificationManager()

    private init() {}

    /// Requests user authorization for notifications if not yet determined.
    public func requestAuthorizationIfNeeded() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            if settings.authorizationStatus == .notDetermined {
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                    if let error {
                        print("[DownloadNotificationManager] Authorization request failed: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    /// Posts a local notification when an item completes downloading.
    public func notifyItemCompleted(
        title: String,
        seriesName: String?,
        isLastItem: Bool,
        remainingCount: Int
    ) {
        let content = UNMutableNotificationContent()
        content.sound = .default

        if isLastItem {
            content.title = "All Downloads Complete"
            if let seriesName, !seriesName.isEmpty, title != seriesName {
                content.body = "'\(title)' finished downloading. All queued downloads are ready to watch offline."
            } else {
                content.body = "'\(title)' is ready to watch offline."
            }
        } else {
            content.title = "Download Complete"
            if remainingCount > 0 {
                let remainingText = remainingCount == 1 ? "1 item remaining" : "\(remainingCount) items remaining"
                content.body = "'\(title)' finished downloading (\(remainingText))."
            } else {
                content.body = "'\(title)' is ready to watch offline."
            }
        }

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let identifier = "download-complete-\(UUID().uuidString)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("[DownloadNotificationManager] Failed to schedule notification: \(error.localizedDescription)")
            }
        }
    }

    /// Posts a local notification if an item fails to download.
    public func notifyItemFailed(title: String, error: String?) {
        let content = UNMutableNotificationContent()
        content.title = "Download Failed"
        content.body = "Failed to download '\(title)'\(error != nil ? ": \(error!)" : ".")."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let identifier = "download-failed-\(UUID().uuidString)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request) { _ in }
    }
}
