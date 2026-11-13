//
//  Manager.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 10/8/26.
//

import Foundation
import Observation
import JellyfinAPI
import LoggingKit

/// Coordinates the sequential offline download pipeline: it owns the persisted download records,
/// the queue, and the background URLSession that fetches media from the server.
///
/// Related behavior lives in focused extensions:
/// - `Manager+Downloads.swift` — starting, queueing, cancelling, and deleting downloads
/// - `Manager+Queries.swift` — read-only state and per-item lookups
/// - `Manager+Transfer.swift` — transfer callbacks, post-processing, and failure recovery
/// - `Manager+LiveActivity.swift` — Live Activity presentation updates
/// - `Manager+URLSession.swift` — background URLSession delegate callbacks
@Observable
@MainActor
public final class DownloadManager: NSObject, URLSessionDownloadDelegate {
    public static let shared = DownloadManager()

    public internal(set) var downloads: [String: DownloadItem] = [:]

    public var client: JellyfinClient? {
        didSet {
            if client != nil {
                processQueue()
            }
        }
    }

    /// Download records persistence and file management.
    @ObservationIgnored
    let storage = DownloadStorage()

    /// Throttled download and conversion progress calculations.
    @ObservationIgnored
    let progressTracker = DownloadProgressTracker()

    /// IDs waiting to be downloaded, in strict playback order.
    @ObservationIgnored
    var downloadQueue: [String] = []

    /// The single download currently owned by the session (downloads are strictly sequential).
    @ObservationIgnored
    var activeDownloadingID: String?

    @ObservationIgnored
    var activeTasks: [String: URLSessionDownloadTask] = [:]
    @ObservationIgnored
    var resumeDataMap: [String: Data] = [:]
    @ObservationIgnored
    var retryAttempts: [String: Int] = [:]
    @ObservationIgnored
    var session: URLSession!

    /// Live Activity thumbnails keyed by poster URL, avoiding repeated downsampling.
    @ObservationIgnored
    var cachedPosterThumbnails: [String: Data] = [:]

    @ObservationIgnored
    private var backgroundCompletionHandlers: [String: () -> Void] = [:]

    public var downloadsDirectory: URL {
        storage.downloadsDirectory
    }

    public override init() {
        super.init()
        let config = URLSessionConfiguration.background(withIdentifier: "com.jellyboi.downloadSession")
        config.sessionSendsLaunchEvents = true
        config.isDiscretionary = false
        config.waitsForConnectivity = true
        config.timeoutIntervalForResource = 3600 * 6 // 6 hours max for large movies
        config.timeoutIntervalForRequest = 180 // 3 minutes timeout for individual chunks
        let delegateQueue = OperationQueue()
        delegateQueue.name = "com.jellyboi.downloadQueue"
        delegateQueue.maxConcurrentOperationCount = 1
        self.session = URLSession(configuration: config, delegate: self, delegateQueue: delegateQueue)

        let loaded = storage.loadIndex()
        self.downloads = loaded.items
        self.downloadQueue = loaded.queue
        let validFileNames = Set(loaded.items.values.map(\.fileName))
        storage.cleanupOrphanedFiles(validFileNames: validFileNames)
        if loaded.didHeal {
            saveIndex()
        }

        // Reconnect to any background tasks already in progress by the daemon
        self.session.getAllTasks { [weak self] tasks in
            Task { @MainActor in
                guard let self else { return }
                for task in tasks {
                    guard let downloadTask = task as? URLSessionDownloadTask,
                          let itemID = downloadTask.taskDescription else { continue }
                    self.activeTasks[itemID] = downloadTask
                    if downloadTask.state == .running || downloadTask.state == .suspended {
                        if self.activeDownloadingID == nil {
                            self.activeDownloadingID = itemID
                        }
                    }
                }
                self.processQueue()
            }
        }

        if client != nil || canRestoreClientFromKeychain {
            processQueue()
        }

        NotificationCenter.default.addObserver(
            forName: .mediaProgressUpdated,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let itemID = notification.object as? String,
                  let positionTicks = notification.userInfo?["positionTicks"] as? Int else { return }
            let totalTicks = notification.userInfo?["durationTicks"] as? Int
            MainActor.assumeIsolated {
                self.updateProgress(for: itemID, positionTicks: positionTicks, totalTicks: totalTicks)
            }
        }

        NotificationCenter.default.addObserver(
            forName: .mediaUserDataChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let dtos = notification.userInfo?["userData"] as? [UserItemDataDto] else { return }
            MainActor.assumeIsolated {
                self.applyUserData(dtos)
            }
        }
    }

    // MARK: - Background URLSession System Handling

    public func handleEventsForBackgroundURLSession(identifier: String, completionHandler: @escaping () -> Void) {
        AppLogger.info("Storing background URLSession completion handler for \(identifier)")
        backgroundCompletionHandlers[identifier] = completionHandler
    }

    public func callBackgroundCompletionHandlerIfNeeded() {
        if let completion = backgroundCompletionHandlers.removeValue(forKey: "com.jellyboi.downloadSession") {
            AppLogger.info("Executing background URLSession completion handler")
            completion()
        }
    }

    // MARK: - Jellyfin Client Restoration

    private var canRestoreClientFromKeychain: Bool {
        KeychainStore.read(StoredSession.self, for: storedSessionKeychainKey) != nil
    }

    /// Returns the in-memory client, or rebuilds one from the stored session so downloads started by
    /// the background daemon can continue without a foreground launch.
    func getOrRestoreClient() -> JellyfinClient? {
        if let client = self.client {
            return client
        }
        guard let session = KeychainStore.read(StoredSession.self, for: storedSessionKeychainKey) else {
            return nil
        }
        let restored = JellyfinClient(configuration: .init(
            url: session.serverURL,
            accessToken: session.token,
            client: "JellyBoi",
            deviceName: PlatformDevice.name,
            deviceID: PlatformDevice.identifier,
            version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        ))
        self.client = restored
        AppLogger.info("Recreated JellyfinClient from Keychain for background downloads")
        return restored
    }

    // MARK: - Persistence

    func saveIndex() {
        storage.saveIndex(items: Array(downloads.values))
    }
}
