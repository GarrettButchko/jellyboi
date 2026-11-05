//
//  PreferencesSettingsView.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 11/05/26.
//

import SwiftUI
import BaseColors

struct PreferencesSettingsView: View {
    @Environment(AppPreferences.self) private var preferencesEnvironment
    @Environment(\.dismiss) private var dismiss

    // Fallback accessor to support both environment and shared singleton
    private var preferences: AppPreferences {
        preferencesEnvironment
    }

    @State private var showResetConfirmation = false

    var body: some View {
        @Bindable var bindablePreferences = preferences

        List {
            // MARK: - Accent Color Section
            Section {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("Theme Accent")
                            .font(.system(.body, design: .rounded, weight: .semibold))
                            .foregroundStyle(Color.mainOpp)

                        Spacer()

                        Text(preferences.accentColorChoice.displayName)
                            .font(.system(.subheadline, design: .rounded, weight: .medium))
                            .foregroundStyle(preferences.accentColor)
                    }

                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 44), spacing: 12)],
                        spacing: 12
                    ) {
                        ForEach(AppAccentColor.allCases) { choice in
                            accentColorCircle(for: choice)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .padding(.vertical, 6)
            } header: {
                Text("Appearance")
            } footer: {
                Text("Changes the accent color applied to buttons, indicators, and navigation elements across the app.")
            }

            // MARK: - Progress Bar Section
            Section {
                Toggle(isOn: $bindablePreferences.showGlassProgressBar) {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.indigo.gradient)
                                .frame(width: 30, height: 30)

                            Image(systemName: "chart.bar.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Glass Progress Bar")
                                .font(.system(.body, design: .rounded, weight: .semibold))
                                .foregroundStyle(Color.mainOpp)

                            Text("Show on media cards & carousel")
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(Color.mainOpp.opacity(0.6))
                        }
                    }
                }
                .tint(.green)
                .padding(.vertical, 2)
            } header: {
                Text("Playback & Progress")
            } footer: {
                Text("When enabled, an ambient frosted glass bar indicates your watch progress on poster cards and the hero carousel.")
            }

            // MARK: - Blurred Backgrounds Section
            Section {
                Toggle(isOn: $bindablePreferences.showHomeBlurredBackdrop) {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.purple.gradient)
                                .frame(width: 30, height: 30)

                            Image(systemName: "house.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Home Blurred Backdrop")
                                .font(.system(.body, design: .rounded, weight: .semibold))
                                .foregroundStyle(Color.mainOpp)

                            Text("Ambient background behind hero carousel")
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(Color.mainOpp.opacity(0.6))
                        }
                    }
                }
                .tint(.green)
                .padding(.vertical, 2)

                Toggle(isOn: $bindablePreferences.showDetailBlurredBackdrop) {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.teal.gradient)
                                .frame(width: 30, height: 30)

                            Image(systemName: "play.rectangle.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Media Details Blurred Backdrop")
                                .font(.system(.body, design: .rounded, weight: .semibold))
                                .foregroundStyle(Color.mainOpp)

                            Text("Ambient background behind title details")
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(Color.mainOpp.opacity(0.6))
                        }
                    }
                }
                .tint(.green)
                .padding(.vertical, 2)
            } header: {
                Text("Blurred Backdrops")
            } footer: {
                Text("Turn off blurred background artwork to reduce visual distraction or enhance performance on older devices.")
            }

            // MARK: - Reset Section
            Section {
                Button(role: .destructive) {
                    showResetConfirmation = true
                } label: {
                    HStack {
                        Spacer()
                        Text("Reset Preferences to Defaults")
                            .font(.system(.body, design: .rounded, weight: .medium))
                        Spacer()
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.bg.ignoresSafeArea())
        .toggleStyle(SwitchToggleStyle(tint: .green))
        .navigationTitle("Preferences")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Reset Preferences?",
            isPresented: $showResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset to Defaults", role: .destructive) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    preferences.resetToDefaults()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will restore default accent color, progress bar visibility, and blurred backdrops.")
        }
    }

    // MARK: - Color Circle Swatch

    @ViewBuilder
    private func accentColorCircle(for choice: AppAccentColor) -> some View {
        let isSelected = preferences.accentColorChoice == choice

        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                preferences.accentColorChoice = choice
            }
        } label: {
            ZStack {
                Circle()
                    .fill(choice.color)
                    .frame(width: 42, height: 42)

                if isSelected {
                    Circle()
                        .strokeBorder(Color.white, lineWidth: 2.5)
                        .frame(width: 42, height: 42)

                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.white)
                }
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .scaleEffect(isSelected ? 1.08 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isSelected)
        .accessibilityLabel(choice.displayName)
    }
}
