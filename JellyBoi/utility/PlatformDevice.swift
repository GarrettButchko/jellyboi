//
//  PlatformDevice.swift
//  JellyBoi
//
//  Created for cross-platform hardware abstraction.
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Provides platform-agnostic device identity (name and unique identifier).
public enum PlatformDevice {

    /// A human-readable device name (e.g. "Garrett's iPhone", "Garrett's MacBook Pro", "Living Room Apple TV").
    public static var name: String {
        #if os(macOS)
        return Host.current().localizedName ?? "Mac"
        #elseif canImport(UIKit)
        return UIDevice.current.name
        #else
        return "Apple Device"
        #endif
    }

    /// A persistent vendor identifier or fallback UUID for device registration.
    public static var identifier: String {
        #if canImport(UIKit)
        if let id = UIDevice.current.identifierForVendor?.uuidString {
            return id
        }
        #endif

        // Persistent fallback across launches for macOS or devices without identifierForVendor
        let defaultsKey = "jellyboi_platform_device_identifier"
        if let saved = UserDefaults.standard.string(forKey: defaultsKey) {
            return saved
        }
        let newID = UUID().uuidString
        UserDefaults.standard.set(newID, forKey: defaultsKey)
        return newID
    }
}
