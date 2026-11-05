//
//  DebugSettings.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 10/6/26.
//

#if DEBUG
import SwiftUI
import Observation
import BaseColors

@Observable
public final class DebugSettings {
    public static let shared = DebugSettings()

    // MARK: - Home Tab
    public var simulateEmptyLibrary = false
    public var simulateLibraryError = false
    public var hideAllHomeRows = false
    public var hideCollections = false
    public var hideContinueWatching = false
    public var hideContinueShows = false
    public var hideTopRated = false
    public var hideRecentlyAddedMovies = false
    public var hideRecentlyAddedShows = false

    // MARK: - Media Tab
    public var simulateMediaEmptyLibrary = false
    public var hideMediaMovies = false
    public var hideMediaShows = false
    public var hideMediaFavorites = false
    public var simulateMediaError = false

    // MARK: - Search Tab
    public var simulateSearchEmptyLibrary = false
    public var hideSearchGenres = false
    public var hideSearchResults = false
    public var hideGenreResults = false

    // MARK: - Media Detail
    public var hideOverview = false
    public var hideBackdrop = false
    public var hidePoster = false
    public var hideCastAndCrew = false
    public var hideEpisodes = false
    public var hideSpecialFeatures = false
    public var hideTags = false
    public var hideSimilarItems = false

    // MARK: - Cast & Crew
    public var hidePersonMedia = false
    public var hidePersonBiography = false
    public var hidePersonImage = false

    // MARK: - Downloads & Offline Playback
    public var showPlaybackDebugOverlay = false
    public var forceStreamFallback = false
    public var simulateRemuxFailure = false

    // MARK: - Performance & Diagnostics
    public var showFPSCounter = false

    public var activeOverrideCount: Int {
        var count = 0
        // Home
        if simulateEmptyLibrary { count += 1 }
        if simulateLibraryError { count += 1 }
        if hideAllHomeRows { count += 1 }
        if hideCollections { count += 1 }
        if hideContinueWatching { count += 1 }
        if hideContinueShows { count += 1 }
        if hideTopRated { count += 1 }
        if hideRecentlyAddedMovies { count += 1 }
        if hideRecentlyAddedShows { count += 1 }
        // Media
        if simulateMediaEmptyLibrary { count += 1 }
        if hideMediaMovies { count += 1 }
        if hideMediaShows { count += 1 }
        if hideMediaFavorites { count += 1 }
        if simulateMediaError { count += 1 }
        // Search
        if simulateSearchEmptyLibrary { count += 1 }
        if hideSearchGenres { count += 1 }
        if hideSearchResults { count += 1 }
        if hideGenreResults { count += 1 }
        // Media Detail
        if hideOverview { count += 1 }
        if hideBackdrop { count += 1 }
        if hidePoster { count += 1 }
        if hideCastAndCrew { count += 1 }
        if hideEpisodes { count += 1 }
        if hideTags { count += 1 }
        if hideSimilarItems { count += 1 }
        // Cast & Crew
        if hidePersonMedia { count += 1 }
        if hidePersonBiography { count += 1 }
        if hidePersonImage { count += 1 }
        // Downloads & Playback
        if showPlaybackDebugOverlay { count += 1 }
        if forceStreamFallback { count += 1 }
        if simulateRemuxFailure { count += 1 }
        // Performance
        if showFPSCounter { count += 1 }
        return count
    }

    public var isAnyActive: Bool {
        activeOverrideCount > 0
    }

    public func reset() {
        simulateEmptyLibrary = false
        simulateLibraryError = false
        hideAllHomeRows = false
        hideCollections = false
        hideContinueWatching = false
        hideContinueShows = false
        hideTopRated = false
        hideRecentlyAddedMovies = false
        hideRecentlyAddedShows = false

        simulateMediaEmptyLibrary = false
        hideMediaMovies = false
        hideMediaShows = false
        hideMediaFavorites = false
        simulateMediaError = false

        simulateSearchEmptyLibrary = false
        hideSearchGenres = false
        hideSearchResults = false
        hideGenreResults = false

        hideOverview = false
        hideBackdrop = false
        hidePoster = false
        hideCastAndCrew = false
        hideEpisodes = false
        hideSpecialFeatures = false
        hideTags = false
        hideSimilarItems = false

        hidePersonMedia = false
        hidePersonBiography = false
        hidePersonImage = false

        showPlaybackDebugOverlay = false
        forceStreamFallback = false
        simulateRemuxFailure = false

        showFPSCounter = false
    }
}

// MARK: - Debug Settings View

public struct DebugSettingsView: View {
    @Bindable var debugSettings = DebugSettings.shared
    @Environment(\.dismiss) private var dismiss

    public var body: some View {
        List {
            // Header banner
            Section {
                HStack(spacing: 12) {
                    Image(systemName: "ladybug.fill")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.orange)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("DEBUG BUILD ONLY")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.orange)
                        Text("Toggle empty fields and missing data states across all tabs to test UI resilience.")
                            .font(.system(.footnote, design: .rounded))
                            .foregroundStyle(Color.mainOpp.opacity(0.7))
                    }
                }
                .padding(.vertical, 4)
            }

            // MARK: - Home Tab
            Section {
                Toggle("Simulate Empty Library", isOn: $debugSettings.simulateEmptyLibrary)
                Toggle("Simulate Library Error", isOn: $debugSettings.simulateLibraryError)
                Toggle("Hide All Home Rows", isOn: $debugSettings.hideAllHomeRows)
                Toggle("Hide Collections", isOn: $debugSettings.hideCollections)
                    .disabled(debugSettings.hideAllHomeRows)
                Toggle("Hide Continue Watching", isOn: $debugSettings.hideContinueWatching)
                    .disabled(debugSettings.hideAllHomeRows)
                Toggle("Hide Continue Watching Shows", isOn: $debugSettings.hideContinueShows)
                    .disabled(debugSettings.hideAllHomeRows)
                Toggle("Hide Top Rated Movies", isOn: $debugSettings.hideTopRated)
                    .disabled(debugSettings.hideAllHomeRows)
                Toggle("Hide Recently Added Movies", isOn: $debugSettings.hideRecentlyAddedMovies)
                    .disabled(debugSettings.hideAllHomeRows)
                Toggle("Hide Recently Added Shows", isOn: $debugSettings.hideRecentlyAddedShows)
                    .disabled(debugSettings.hideAllHomeRows)
            } header: {
                Label("Home Tab", systemImage: "house")
            } footer: {
                Text("Simulates empty rows, missing sections, and connection error states on the Home feed.")
            }

            // MARK: - Media Tab
            Section {
                Toggle("Simulate Empty Library", isOn: $debugSettings.simulateMediaEmptyLibrary)
                Toggle("Simulate Library Error", isOn: $debugSettings.simulateMediaError)
                Toggle("Hide Movies Tab", isOn: $debugSettings.hideMediaMovies)
                Toggle("Hide TV Shows Tab", isOn: $debugSettings.hideMediaShows)
                Toggle("Hide Favorites Filter", isOn: $debugSettings.hideMediaFavorites)
            } header: {
                Label("Media Tab", systemImage: "play.rectangle.on.rectangle")
            } footer: {
                Text("Simulates empty library grids, missing category items, or library fetch failures.")
            }

            // MARK: - Search Tab
            Section {
                Toggle("Simulate Empty Library", isOn: $debugSettings.simulateSearchEmptyLibrary)
                Toggle("Hide Search Genres", isOn: $debugSettings.hideSearchGenres)
                Toggle("Simulate No Search Results", isOn: $debugSettings.hideSearchResults)
                    .disabled(debugSettings.simulateSearchEmptyLibrary)
                Toggle("Simulate Empty Genre View", isOn: $debugSettings.hideGenreResults)
                    .disabled(debugSettings.simulateSearchEmptyLibrary)
            } header: {
                Label("Search Tab", systemImage: "magnifyingglass")
            } footer: {
                Text("Simulates an empty library in Search ('No Media in Library'), or missing query results and empty genre lists.")
            }

            // MARK: - Media Detail View
            Section {
                Toggle("Hide Overview / Summary", isOn: $debugSettings.hideOverview)
                Toggle("Hide Backdrop Image", isOn: $debugSettings.hideBackdrop)
                Toggle("Hide Poster Image", isOn: $debugSettings.hidePoster)
                Toggle("Hide Cast & Crew", isOn: $debugSettings.hideCastAndCrew)
                Toggle("Hide Episodes", isOn: $debugSettings.hideEpisodes)
                Toggle("Hide Special Features", isOn: $debugSettings.hideSpecialFeatures)
                Toggle("Hide Tags", isOn: $debugSettings.hideTags)
                Toggle("Hide 'More Like This'", isOn: $debugSettings.hideSimilarItems)
            } header: {
                Label("Media Detail", systemImage: "info.circle")
            } footer: {
                Text("Simulates media items with missing metadata, absent artwork, or empty cast.")
            }

            // MARK: - Cast & Crew View
            Section {
                Toggle("Hide Person Media", isOn: $debugSettings.hidePersonMedia)
                Toggle("Hide Person Biography", isOn: $debugSettings.hidePersonBiography)
                Toggle("Hide Person Photo", isOn: $debugSettings.hidePersonImage)
            } header: {
                Label("Cast & Crew Detail", systemImage: "person.2")
            } footer: {
                Text("Tests person profiles with missing biographies, placeholder avatar, or empty media credits.")
            }

            // MARK: - Downloads & Offline Playback
            Section {
                Toggle("Show Playback Info HUD", isOn: $debugSettings.showPlaybackDebugOverlay)
                Toggle("Force Streaming (Bypass Local File)", isOn: $debugSettings.forceStreamFallback)
                Toggle("Simulate Remux Failure", isOn: $debugSettings.simulateRemuxFailure)
            } header: {
                Label("Downloads & Offline Playback", systemImage: "arrow.down.circle")
            } footer: {
                Text("Displays video/audio track diagnostics on top of the player, forces server streaming even if a local file exists, or tests remuxing error handling.")
            }

            // MARK: - Performance & Diagnostics
            Section {
                Toggle("Show Framerate (FPS) Counter", isOn: $debugSettings.showFPSCounter)
            } header: {
                Label("Performance & Diagnostics", systemImage: "gauge.with.dots.needle.bottom.50percent")
            } footer: {
                Text("Displays a real-time floating FPS, min FPS, and frame time overlay across all screens for hitch and animation testing.")
            }

            // MARK: - Reset All
            if debugSettings.isAnyActive {
                Section {
                    Button(role: .destructive) {
                        withAnimation {
                            debugSettings.reset()
                        }
                    } label: {
                        HStack {
                            Spacer()
                            Text("Reset All Debug Toggles (\(debugSettings.activeOverrideCount))")
                                .font(.system(.body, design: .rounded, weight: .semibold))
                            Spacer()
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.bg.ignoresSafeArea())
        .navigationTitle("Debug Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}
#endif
