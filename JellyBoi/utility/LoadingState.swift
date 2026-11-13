//
//  LoadingState.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 9/2/26.
//

import Foundation
import JellyfinAPI

// MARK: - Detail Section Status

public enum DetailSectionStatus: Equatable, Hashable, Sendable {
    case idle
    case loading
    case loaded
    case empty

    public var isLoading: Bool { self == .loading }
    public var isLoaded: Bool { self == .loaded }
    public var isEmpty: Bool { self == .empty }
    public var isIdle: Bool { self == .idle }
}
