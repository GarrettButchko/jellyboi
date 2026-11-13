//
//  NetworkMonitor.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 10/23/26.
//

import Foundation
import Network
import Observation
import LoggingKit

extension Notification.Name {
    static let networkStatusDidChange = Notification.Name("com.jellyboi.networkStatusDidChange")
}

@Observable
public final class NetworkMonitor: @unchecked Sendable {
    public static let shared = NetworkMonitor()

    public private(set) var isConnected: Bool
    public private(set) var isExpensive: Bool = false
    public private(set) var isConstrained: Bool = false
    public private(set) var hasReceivedFirstUpdate: Bool = false

    @ObservationIgnored
    private let monitor = NWPathMonitor()

    @ObservationIgnored
    private let queue = DispatchQueue(label: "com.jellyboi.networkmonitor", qos: .userInitiated)

    public init() {
        self.isConnected = true
        self.hasReceivedFirstUpdate = false

        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let connected = path.status == .satisfied
                let statusChanged = !self.hasReceivedFirstUpdate || self.isConnected != connected

                self.isConnected = connected
                self.isExpensive = path.isExpensive
                self.isConstrained = path.isConstrained
                self.hasReceivedFirstUpdate = true

                if statusChanged {
                    AppLogger.info("Network path changed: status=\(path.status), isConnected=\(connected)")
                    NotificationCenter.default.post(
                        name: .networkStatusDidChange,
                        object: self,
                        userInfo: ["isConnected": connected]
                    )
                }
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }

    public func setConnected(_ connected: Bool) {
        guard !hasReceivedFirstUpdate || self.isConnected != connected else { return }
        self.isConnected = connected
        self.hasReceivedFirstUpdate = true
        NotificationCenter.default.post(
            name: .networkStatusDidChange,
            object: self,
            userInfo: ["isConnected": connected]
        )
    }

    @discardableResult
    public func checkConnection() async -> Bool {
        let connected = monitor.currentPath.status == .satisfied
        let statusChanged = !self.hasReceivedFirstUpdate || self.isConnected != connected
        self.isConnected = connected
        self.isExpensive = self.monitor.currentPath.isExpensive
        self.isConstrained = self.monitor.currentPath.isConstrained
        self.hasReceivedFirstUpdate = true

        if statusChanged {
            NotificationCenter.default.post(
                name: .networkStatusDidChange,
                object: self,
                userInfo: ["isConnected": connected]
            )
        }
        return connected
    }
}
