//
//  PlatformBackgroundTask.swift
//  JellyBoi
//
//  Created for cross-platform background task abstraction.
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Executes an async closure while requesting background execution time from the host OS if supported.
public enum PlatformBackgroundTask {
    public static func run(
        name: String,
        operation: @escaping () async -> Void
    ) {
        #if os(iOS) || targetEnvironment(macCatalyst)
        var taskID = UIBackgroundTaskIdentifier.invalid
        taskID = UIApplication.shared.beginBackgroundTask(withName: name) {
            if taskID != .invalid {
                UIApplication.shared.endBackgroundTask(taskID)
                taskID = .invalid
            }
        }

        Task {
            defer {
                if taskID != .invalid {
                    UIApplication.shared.endBackgroundTask(taskID)
                    taskID = .invalid
                }
            }
            await operation()
        }
        #elseif os(macOS)
        let activity = ProcessInfo.processInfo.beginActivity(
            options: [.idleSystemSleepDisabled, .suddenTerminationDisabled],
            reason: name
        )
        Task {
            defer {
                ProcessInfo.processInfo.endActivity(activity)
            }
            await operation()
        }
        #else
        Task {
            await operation()
        }
        #endif
    }
}
