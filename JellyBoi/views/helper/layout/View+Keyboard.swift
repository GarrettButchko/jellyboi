//
//  View+Keyboard.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 9/9/26.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

enum KeyboardHelper {
    /// Immediately dismisses the software keyboard across the active window scenes.
    /// Returns true if a responder resigned or window editing ended.
    @discardableResult
    @MainActor
    static func hideKeyboard() -> Bool {
        #if canImport(UIKit)
        let resigned = UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
        var ended = false
        for scene in UIApplication.shared.connectedScenes {
            if let windowScene = scene as? UIWindowScene {
                for window in windowScene.windows {
                    if window.endEditing(true) {
                        ended = true
                    }
                }
            }
        }
        return resigned || ended
        #else
        return false
        #endif
    }

    /// Dismisses the keyboard and, if the keyboard was active or `wasFocused` is true,
    /// waits for the keyboard dismissal animation to complete (~250ms) before executing `action`.
    /// If no keyboard was active, executes `action` immediately.
    @MainActor
    static func dismissThen(wasFocused: Bool = false, action: @escaping @MainActor () -> Void) {
        let resigned = hideKeyboard()
        if wasFocused || resigned {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 250_000_000)
                action()
            }
        } else {
            action()
        }
    }
}

extension View {
    /// Immediately dismisses the software keyboard across the active window.
    @discardableResult
    @MainActor
    func hideKeyboard() -> Bool {
        KeyboardHelper.hideKeyboard()
    }
}

