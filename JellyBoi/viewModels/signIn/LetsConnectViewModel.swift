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

    enum ServerCheckState: Equatable {
        case idle
        case checking
        case verified(name: String)
        case failed(String)
    }

    var discoveredServers: [JellyfinClient.PublicServer] = []
    var isSearching = false
    var serverCheckState: ServerCheckState = .idle
    private(set) var verifiedURL: URL?

    private var discoveryTask: Task<Void, Never>?
    private var checkTask: Task<Void, Never>?

    private let isMock: Bool

    init(mockServers: [JellyfinClient.PublicServer] = []) {
        discoveredServers = mockServers
        isMock = !mockServers.isEmpty
    }

    // MARK: - Discovery

    func startDiscovery() {
        guard !isMock else { return }
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

    // MARK: - Server URL Check

    /// Call whenever the URL field changes. Debounces and hits /System/Info/Public.
    func scheduleServerCheck(urlString: String) {
        checkTask?.cancel()
        serverCheckState = .idle
        verifiedURL = nil

        guard let url = URL(string: urlString),
              let scheme = url.scheme, (scheme == "http" || scheme == "https"),
              let host = url.host, !host.isEmpty else { return }

        serverCheckState = .checking

        checkTask = Task {
            // Debounce — wait for the user to stop typing
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }

            await checkServer(url: url)
        }
    }

    private struct PublicInfoResponse: Decodable {
        let serverName: String?
        enum CodingKeys: String, CodingKey {
            case serverName = "ServerName"
        }
    }

    private func checkServer(url: URL) async {
        let endpoint = url.appendingPathComponent("/System/Info/Public")
        do {
            let (data, response) = try await URLSession.shared.data(from: endpoint)
            guard !Task.isCancelled else { return }
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                serverCheckState = .failed("Couldn't reach a Jellyfin server at this URL")
                verifiedURL = nil
                return
            }
            let info = try JSONDecoder().decode(PublicInfoResponse.self, from: data)
            serverCheckState = .verified(name: info.serverName ?? url.host ?? "Jellyfin Server")
            verifiedURL = url
        } catch {
            guard !Task.isCancelled else { return }
            serverCheckState = .failed("Couldn't reach a Jellyfin server at this URL")
            verifiedURL = nil
        }
    }
}
