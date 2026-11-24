//
//  AppLogRecorder.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 11/4/26.
//

import Foundation
import Observation
import LoggingKit
import Darwin

public enum SystemMetrics: Sendable {
    public static var residentMemoryMB: Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard kerr == KERN_SUCCESS else { return 0.0 }
        return Double(info.resident_size) / (1024.0 * 1024.0)
    }
}

public struct LogRecord: Identifiable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let level: LogLevel
    public let message: String

    public init(id: UUID = UUID(), timestamp: Date = Date(), level: LogLevel, message: String) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.message = message
    }
}

@Observable
public final class AppLogRecorder: @unchecked Sendable {
    public static let shared = AppLogRecorder()

    public private(set) var records: [LogRecord] = []
    private let lock = NSLock()
    private let maxEntries: Int = 1000

    public init() {}

    
    public func start() {
        AppLogger.logHandler = { [weak self] level, message in
            self?.append(level: level, message: message)
        }
    }

    public func append(level: LogLevel, message: String) {
        let entry = LogRecord(level: level, message: message)
        lock.lock()
        if records.count >= maxEntries {
            records.removeFirst(records.count - maxEntries + 1)
        }
        records.append(entry)
        lock.unlock()
    }

    public func clear() {
        lock.lock()
        records.removeAll()
        lock.unlock()
    }

    public func exportLogText() -> String {
        lock.lock()
        let copy = records
        lock.unlock()

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"

        return copy.map { record in
            "[\(formatter.string(from: record.timestamp))] [\(record.level.rawValue)] \(record.message)"
        }.joined(separator: "\n")
    }

    public func exportLogFileURL() -> URL? {
        let text = exportLogText()
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "JellyBoi-Diagnostics-\(Int(Date().timeIntervalSince1970)).log"
        let fileURL = tempDir.appendingPathComponent(fileName)

        do {
            try text.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            return nil
        }
    }
}
