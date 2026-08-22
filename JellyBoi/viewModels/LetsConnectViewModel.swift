//
//  LetsConnectViewModel.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 8/21/26.
//

import Foundation
import Observation
import JellyfinAPI

@Observable
@MainActor
class LetsConnectViewModel {
    var discoveredServers: [JellyfinClient.PublicServer] = []
    var isSearching = false

    private var discoveryTask: Task<Void, Never>?

    func startDiscovery() {
        discoveryTask?.cancel()
        discoveredServers = []
        isSearching = true

        discoveryTask = Task {
            do {
                for try await server in JellyfinClient.discover(duration: .seconds(5)) {
                    if !discoveredServers.contains(server) {
                        discoveredServers.append(server)
                    }
                }
            } catch {}
            isSearching = false
        }
    }

    func stopDiscovery() {
        discoveryTask?.cancel()
        discoveryTask = nil
        isSearching = false
    }
}
