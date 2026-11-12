//
//  LoadingState.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 9/2/26.
//

import Foundation
import JellyfinAPI

// MARK: - Loading State

enum LoadingState<Element> {
    case empty
    case loading
    case full([Element])
}

extension LoadingState: Equatable where Element: Equatable {}
extension LoadingState: Hashable where Element: Hashable {}
extension LoadingState: Sendable where Element: Sendable {}

extension LoadingState {
    var elements: [Element] {
        switch self {
        case .full(let items):
            return items
        case .empty, .loading:
            return []
        }
    }

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    var isFull: Bool {
        if case .full = self { return true }
        return false
    }

    var isEmpty: Bool {
        switch self {
        case .empty, .loading:
            return true
        case .full(let items):
            return items.isEmpty
        }
    }

    static func loaded(_ items: [Element]) -> LoadingState<Element> {
        items.isEmpty ? .empty : .full(items)
    }
}

extension LoadingState: ExpressibleByArrayLiteral {
    init(arrayLiteral elements: Element...) {
        if elements.isEmpty {
            self = .empty
        } else {
            self = .full(elements)
        }
    }
}

extension LoadingState: RandomAccessCollection, MutableCollection {
    typealias Index = Int

    var startIndex: Int { 0 }
    var endIndex: Int {
        switch self {
        case .full(let items):
            return items.count
        case .empty, .loading:
            return 0
        }
    }

    subscript(position: Int) -> Element {
        get {
            switch self {
            case .full(let items):
                return items[position]
            case .empty, .loading:
                fatalError("Index out of bounds")
            }
        }
        set {
            switch self {
            case .full(var items):
                items[position] = newValue
                self = .full(items)
            case .empty, .loading:
                fatalError("Index out of bounds")
            }
        }
    }

    func index(after i: Int) -> Int {
        i + 1
    }

    func index(before i: Int) -> Int {
        i - 1
    }
}

extension LoadingState: CustomStringConvertible {
    var description: String {
        switch self {
        case .empty:
            return "LoadingState.empty"
        case .loading:
            return "LoadingState.loading"
        case .full(let items):
            return "LoadingState.full(\(items.count) items)"
        }
    }
}

extension LoadingState where Element == BaseItemDto {
    mutating func clearProgress(for itemID: String, matchingSeries: Bool = false) {
        guard case .full(var items) = self else { return }
        items.clearProgress(for: itemID, matchingSeries: matchingSeries)
        self = .full(items)
    }

    mutating func updateProgress(for itemID: String, positionTicks: Int, totalTicks: Int?) {
        guard case .full(var items) = self else { return }
        items.updateProgress(for: itemID, positionTicks: positionTicks, totalTicks: totalTicks)
        self = .full(items)
    }

    mutating func updateFavorite(for itemID: String, isFavorite: Bool) {
        guard case .full(var items) = self else { return }
        items.updateFavorite(for: itemID, isFavorite: isFavorite)
        self = .full(items)
    }

    func nextPlayableItem(fromBeginning: Bool = false) -> BaseItemDto? {
        elements.nextPlayableItem(fromBeginning: fromBeginning)
    }
}
