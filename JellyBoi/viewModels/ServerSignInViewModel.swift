//
//  ServerSignInViewModel.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 8/22/26.
//

import Foundation
import Observation
import JellyfinAPI

@Observable
@MainActor
class ServerSignInViewModel {

    enum SignInState: Equatable {
        case idle
        case loading
        case error(String)
    }

    enum QuickConnectState: Equatable {
        case idle
        case polling(code: String)
        case error(String)
    }

    var username = ""
    var password = ""
    var signInState: SignInState = .idle
    var quickConnectState: QuickConnectState = .idle
    var didAuthenticate = false
    private(set) var authenticatedUser: UserDto?
    private(set) var savedToken: String?

    private var quickConnectTask: Task<Void, Never>?

    // MARK: - Username / Password

    func signIn(using client: JellyfinClient) async {
        signInState = .loading
        do {
            let result = try await client.signIn(username: username, password: password)
            guard let token = result.accessToken else {
                signInState = .error("No access token returned")
                return
            }
            savedToken = token
            authenticatedUser = result.user
            didAuthenticate = true
        } catch {
            signInState = .error("Incorrect username or password")
        }
    }

    // MARK: - Quick Connect

    func startQuickConnect(using client: JellyfinClient) {
        quickConnectTask?.cancel()
        quickConnectState = .idle

        quickConnectTask = Task {
            do {
                for try await event in client.quickConnect.connect() {
                    switch event {
                    case .polling(let code):
                        quickConnectState = .polling(code: code)
                    case .authenticated(let secret):
                        let result = try await client.signIn(quickConnectSecret: secret)
                        guard let token = result.accessToken else { return }
                        savedToken = token
                        authenticatedUser = result.user
                        didAuthenticate = true
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                quickConnectState = .error("Quick Connect failed. Make sure it's enabled on the server.")
            }
        }
    }

    func stopQuickConnect() {
        quickConnectTask?.cancel()
        quickConnectTask = nil
        quickConnectState = .idle
    }
}
