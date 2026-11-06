//
//  AppPreferences.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 11/05/26.
//

import SwiftUI
import Observation

/// Available accent colors in JellyBoi
public enum AppAccentColor: String, CaseIterable, Identifiable, Sendable {
    case indigo
    case blue
    case purple
    case pink
    case red
    case orange
    case yellow
    case green
    case mint
    case teal
    case cyan

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .blue: return "Blue"
        case .purple: return "Purple"
        case .indigo: return "Indigo"
        case .pink: return "Pink"
        case .red: return "Red"
        case .orange: return "Orange"
        case .yellow: return "Yellow"
        case .green: return "Green"
        case .mint: return "Mint"
        case .teal: return "Teal"
        case .cyan: return "Cyan"
        }
    }

    public var color: Color {
        switch self {
        case .blue: return Color.blue
        case .purple: return Color.purple
        case .indigo: return Color.indigo
        case .pink: return Color.pink
        case .red: return Color.red
        case .orange: return Color.orange
        case .yellow: return Color.yellow
        case .green: return Color.green
        case .mint: return Color.mint
        case .teal: return Color.teal
        case .cyan: return Color.cyan
        }
    }
}

/// Centralized user preferences backed by UserDefaults.
@Observable
public final class AppPreferences: @unchecked Sendable {
    public static let shared = AppPreferences()

    private enum Keys {
        static let showGlassProgressBar = "app_pref_show_glass_progress_bar"
        static let showHomeCarousel = "app_pref_show_home_carousel"
        static let showHomeBlurredBackdrop = "app_pref_show_home_blurred_backdrop"
        static let showDetailBlurredBackdrop = "app_pref_show_detail_blurred_backdrop"
        static let accentColor = "app_pref_accent_color"
    }

    public var showGlassProgressBar: Bool {
        didSet {
            UserDefaults.standard.set(showGlassProgressBar, forKey: Keys.showGlassProgressBar)
        }
    }

    public var showHomeCarousel: Bool {
        didSet {
            UserDefaults.standard.set(showHomeCarousel, forKey: Keys.showHomeCarousel)
        }
    }

    public var showHomeBlurredBackdrop: Bool {
        didSet {
            UserDefaults.standard.set(showHomeBlurredBackdrop, forKey: Keys.showHomeBlurredBackdrop)
        }
    }

    public var showDetailBlurredBackdrop: Bool {
        didSet {
            UserDefaults.standard.set(showDetailBlurredBackdrop, forKey: Keys.showDetailBlurredBackdrop)
        }
    }

    public var accentColorChoice: AppAccentColor {
        didSet {
            UserDefaults.standard.set(accentColorChoice.rawValue, forKey: Keys.accentColor)
        }
    }

    public var accentColor: Color {
        accentColorChoice.color
    }

    public init() {
        let defaults = UserDefaults.standard

        if defaults.object(forKey: Keys.showGlassProgressBar) == nil {
            self.showGlassProgressBar = true
        } else {
            self.showGlassProgressBar = defaults.bool(forKey: Keys.showGlassProgressBar)
        }

        if defaults.object(forKey: Keys.showHomeCarousel) == nil {
            self.showHomeCarousel = true
        } else {
            self.showHomeCarousel = defaults.bool(forKey: Keys.showHomeCarousel)
        }

        if defaults.object(forKey: Keys.showHomeBlurredBackdrop) == nil {
            self.showHomeBlurredBackdrop = true
        } else {
            self.showHomeBlurredBackdrop = defaults.bool(forKey: Keys.showHomeBlurredBackdrop)
        }

        if defaults.object(forKey: Keys.showDetailBlurredBackdrop) == nil {
            self.showDetailBlurredBackdrop = true
        } else {
            self.showDetailBlurredBackdrop = defaults.bool(forKey: Keys.showDetailBlurredBackdrop)
        }

        if let savedAccent = defaults.string(forKey: Keys.accentColor),
           let choice = AppAccentColor(rawValue: savedAccent) {
            self.accentColorChoice = choice
        } else {
            self.accentColorChoice = .indigo
        }
    }

    public func resetToDefaults() {
        showGlassProgressBar = true
        showHomeCarousel = true
        showHomeBlurredBackdrop = true
        showDetailBlurredBackdrop = true
        accentColorChoice = .indigo
    }
}

extension Color {
    /// App-wide dynamic accent color based on user preferences.
    public static var appAccent: Color {
        AppPreferences.shared.accentColor
    }
}

extension ShapeStyle where Self == Color {
    /// App-wide dynamic accent color based on user preferences.
    public static var appAccent: Color {
        AppPreferences.shared.accentColor
    }
}
