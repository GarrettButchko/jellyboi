//
//  ReadinessBox.swift
//  JellyBoi
//

import Foundation

/// One-shot gate that lets an `AVPlayerItem.status` observer resume a continuation exactly once.
///
/// A ready, failed, and cancelled item can all fire for the same wait, so the closure is cleared
/// after the first resume and concurrent callers get `false`.
nonisolated final class ReadinessBox: @unchecked Sendable {
    private var resumed = false
    private var resumeClosure: ((Bool) -> Void)?
    private let lock = NSLock()

    func setResume(_ closure: @escaping (Bool) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        resumeClosure = closure
    }

    /// Resumes the waiting continuation. Returns `true` when this call won the race.
    @discardableResult
    func resume(returning value: Bool) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !resumed, let closure = resumeClosure else { return false }
        resumed = true
        resumeClosure = nil
        closure(value)
        return true
    }
}
