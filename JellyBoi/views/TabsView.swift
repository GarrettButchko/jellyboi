//
//  TabsView.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 8/19/26.
//

import SwiftUI
import JellyfinAPI
import StatusOverlayKit
import BaseColors
#if os(iOS)
import UIKit
#endif

struct TabsView: View {

    @Environment(ViewManager.self) private var viewManager
    @Environment(ServerViewModel.self) private var serverViewModel
    @Environment(LibraryViewModel.self) private var libraryViewModel
    @Environment(PlaybackManager.self) private var playbackManager
    @Environment(AppPreferences.self) private var preferences
    @Environment(\.colorScheme) private var colorScheme
    @State private var homeViewModel: HomeViewModel
    @State private var mediaViewModel: MediaViewModel
    @State private var searchViewModel: SearchViewModel

    /// Owns the single tab bar overlay shared by every tab's scroll view.
    @State private var scrollOverlayCoordinator = ScrollOverlayCoordinator()

    init(libraryViewModel: LibraryViewModel? = nil) {
        let lib = libraryViewModel ?? LibraryViewModel()
        _homeViewModel = State(initialValue: HomeViewModel(library: lib))
        _mediaViewModel = State(initialValue: MediaViewModel(library: lib))
        _searchViewModel = State(initialValue: SearchViewModel(library: lib))
    }

    private func syncViewModels() {
        if homeViewModel.library !== libraryViewModel {
            homeViewModel.library = libraryViewModel
        }
        if mediaViewModel.library !== libraryViewModel {
            mediaViewModel.library = libraryViewModel
        }
        if searchViewModel.library !== libraryViewModel {
            searchViewModel.library = libraryViewModel
        }
    }

    var body: some View {
        @Bindable var bindableViewManager = viewManager
        TabView(selection: $bindableViewManager.selectedTab) {
            Tab("Home", systemImage: "house", value: AppTab.home) {
                tabContent { HomeView() }
            }

            Tab("Media", systemImage: "rectangle.stack", value: AppTab.media) {
                tabContent { MediaView() }
            }

            // The search role makes the tab bar own the search field, like Apple's apps.
            // `SearchView` applies `searchable` inside its NavigationStack, which is
            // where the search tab looks for the field to host in the tab bar.
            Tab(value: AppTab.search, role: .search) {
                tabContent { SearchView() }
            }

        }
        // Selecting the search tab activates the tab bar's search field directly.
        .tabViewSearchActivation(.searchTabSelection)
        .background(Color.bg.ignoresSafeArea())
        
        .environment(scrollOverlayCoordinator)
        .environment(homeViewModel)
        .environment(mediaViewModel)
        .environment(searchViewModel)
        .task {
            syncViewModels()
            playbackManager.client = serverViewModel.client
            playbackManager.userID = serverViewModel.currentUser?.id
            playbackManager.libraryViewModel = libraryViewModel
            if libraryViewModel.isLibraryEmpty, let client = serverViewModel.client {
                await libraryViewModel.load(using: client, userID: serverViewModel.currentUser?.id)
            }
        }
        .onAppear {
            syncViewModels()
            updateTabBarTint()
            // SwiftUI can install the underlying `UITabBar` after the first
            // appearance pass, so re-apply once the current update completes.
            DispatchQueue.main.async {
                updateTabBarTint()
            }
        }
        .onChange(of: preferences.accentColorChoice) { _, _ in
            updateTabBarTint()
        }
        .onChange(of: serverViewModel.client != nil) { _, _ in
            syncViewModels()
            playbackManager.client = serverViewModel.client
            playbackManager.userID = serverViewModel.currentUser?.id
        }
    }

    /// Keeps the floating download / scroll-to-top bar above the tab bar on every tab.
    private func tabContent<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .overlay(alignment: .bottom) {
                if viewManager.selectedTab != .search {
                    ScrollTabBarOverlay(
                        isVisible: scrollOverlayCoordinator.isScrollToTopVisible,
                        action: scrollOverlayCoordinator.scrollToTop
                    )
                    .safeAreaPadding(.bottom, 8)
                }
            }
    }

    /// Tints only the tab bar's selected item. Using the SwiftUI `tint(_:)`
    /// modifier on the `TabView` would also tint every control inside the tabs,
    /// so the color is applied directly to the underlying `UITabBar`'s
    /// appearance instead. The selected item colors are set on the appearance
    /// object because SwiftUI reapplies its own `tintColor` to the bar.
    private func updateTabBarTint() {
        #if os(iOS)
        let uiColor = UIColor(preferences.accentColor)

        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows {
                Self.updateTabBars(in: window, color: uiColor)
            }
        }
        #endif
    }

    #if os(iOS)
    private static func updateTabBars(in view: UIView, color: UIColor) {
        if let tabBar = view as? UITabBar {
            tabBar.tintColor = color

            let selectedAttributes: [NSAttributedString.Key: Any] = [
                .foregroundColor: color
            ]

            if let standardAppearance = tabBar.standardAppearance.copy() as? UITabBarAppearance {
                applySelectedAppearance(
                    to: standardAppearance,
                    color: color,
                    titleAttributes: selectedAttributes
                )
                tabBar.standardAppearance = standardAppearance
            }

            if let scrollEdgeAppearance = tabBar.scrollEdgeAppearance?.copy() as? UITabBarAppearance {
                applySelectedAppearance(
                    to: scrollEdgeAppearance,
                    color: color,
                    titleAttributes: selectedAttributes
                )
                tabBar.scrollEdgeAppearance = scrollEdgeAppearance
            }
        }

        for subview in view.subviews {
            updateTabBars(in: subview, color: color)
        }
    }

    private static func applySelectedAppearance(
        to appearance: UITabBarAppearance,
        color: UIColor,
        titleAttributes: [NSAttributedString.Key: Any]
    ) {
        for itemAppearance in [
            appearance.stackedLayoutAppearance,
            appearance.inlineLayoutAppearance,
            appearance.compactInlineLayoutAppearance
        ] {
            itemAppearance.selected.iconColor = color
            itemAppearance.selected.titleTextAttributes = titleAttributes
        }
    }
    #endif
}
