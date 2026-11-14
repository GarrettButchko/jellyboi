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

    /// Completed downloads, newest first, refreshed only when the index changes shape.
    ///
    /// Views read this instead of `downloads` so progress ticks for an in-flight download don't
    /// invalidate every screen that lists downloaded media.
    public internal(set) var completedSnapshot: [DownloadItem] = []

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

    /// True while an index write is in flight, so bursts of changes collapse into one write.
    @ObservationIgnored
    private var isSavingIndex = false

    /// Set when a change arrives while a write is already running.
    @ObservationIgnored
    private var indexSavePending = false

    /// Set when item metadata inside the completed snapshot changed without the record itself
    /// comparing differently (`DownloadItem.==` intentionally ignores `item`).
    @ObservationIgnored
    private var completedSnapshotNeedsRefresh = false

    @ObservationIgnored
    private var backgroundCompletionHandlers: [String: () -> Void] = [:]

    /// True while the persisted download index is still being read back at launch.
    @ObservationIgnored
    var isRestoringDownloads = false

    /// Main-actor work waiting for the persisted downloads to finish loading.
    @ObservationIgnored
    private var restoreWaiters: [CheckedContinuation<Void, Never>] = []

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

        // Reading the index back means decoding JSON, checking every recorded file on disk, and
        // sweeping the Downloads directory for orphans. That is too much I/O to do before the
        // first frame, so it runs on a background task and is applied to the observable state on
        // the main actor.
        isRestoringDownloads = true
        let clientIsSet = client != nil
        Task {
            // Keychain reads are cheap, so they stay on the main actor; only the bool crosses over.
            let canStartQueue = clientIsSet
                || KeychainStore.read(StoredSession.self, for: storedSessionKeychainKey) != nil
            let storage = self.storage
            let restored = await Task.detached(priority: .userInitiated) {
                let loaded = storage.loadIndex()
                storage.cleanupOrphanedFiles(
                    validFileNames: Set(loaded.items.values.map(\.fileName))
                )
                return RestoredDownloads(
                    items: loaded.items,
                    queue: loaded.queue,
                    didHeal: loaded.didHeal,
                    canStartQueue: canStartQueue
                )
            }.value

            self.downloads = restored.items
            self.downloadQueue = restored.queue
            self.refreshCompletedSnapshot()
            if restored.didHeal {
                self.saveIndex()
            }
            self.finishRestoringDownloads()
            if restored.canStartQueue {
                self.processQueue()
            }
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

    // MARK: - Index Restoration

    /// Runs `work` on the main actor once the persisted downloads are available, so launch-time
    /// background-session callbacks never observe an empty index.
    func afterDownloadsRestore(_ work: @escaping @MainActor () -> Void) {
        guard isRestoringDownloads else {
            work()
            return
        }
        Task { @MainActor in
            await waitForDownloadsRestore()
            work()
        }
    }

    private func waitForDownloadsRestore() async {
        guard isRestoringDownloads else { return }
        await withCheckedContinuation { continuation in
            restoreWaiters.append(continuation)
        }
    }

    private func finishRestoringDownloads() {
        isRestoringDownloads = false
        let waiters = restoreWaiters
        restoreWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    // MARK: - Jellyfin Client Restoration

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
        refreshCompletedSnapshot()

        // Encoding the whole index and writing it atomically is disk work that used to run on the
        // main actor for every queue/state change. Keep it off the main thread and fold bursts of
        // changes into a single write.
        guard !isSavingIndex else {
            indexSavePending = true
            return
        }
        isSavingIndex = true
        let snapshot = Array(downloads.values)
        let storage = self.storage
        Task.detached(priority: .utility) {
            storage.saveIndex(items: snapshot)
            await self.finishIndexSave()
        }
    }

    private func finishIndexSave() {
        isSavingIndex = false
        guard indexSavePending else { return }
        indexSavePending = false
        saveIndex()
    }

    /// Rebuilds `completedSnapshot`. Only reassigns when the result actually changed so observers
    /// of download state are not invalidated by progress-only updates.
    func refreshCompletedSnapshot() {
        let completed = downloads.values
            .filter { $0.status == .completed && storage.fileExists(for: $0.fileName) }
            .sorted { ($0.dateCompleted ?? $0.dateAdded) > ($1.dateCompleted ?? $1.dateAdded) }

        // `DownloadItem`'s equality ignores its metadata, so item updates (playback position,
        // favorites) have to flag themselves to get through the guard below.
        let metadataChanged = completedSnapshotNeedsRefresh
        completedSnapshotNeedsRefresh = false

        guard metadataChanged || completed != completedSnapshot else { return }
        completedSnapshot = completed
    }

    /// Marks the completed snapshot as stale even if the records themselves compare equal.
    func markCompletedSnapshotMetadataDirty() {
        completedSnapshotNeedsRefresh = true
    }
}

/// Persisted download state read back off the main actor during launch.
private struct RestoredDownloads: Sendable {
    let items: [String: DownloadItem]
    let queue: [String]
    let didHeal: Bool
    let canStartQueue: Bool
}

/// Carries a URLSession error across the short wait for the downloads index to finish loading.
struct DeferredDownloadError: @unchecked Sendable {
    let value: Error

    init(_ value: Error) {
        self.value = value
    }
}
