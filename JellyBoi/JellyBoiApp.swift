//
//  JellyBoiApp.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 8/19/26.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
import LoggingKit
import StatusOverlayKit

#if os(iOS)
final class AppDelegate: NSObject, UIApplicationDelegate {
    static var orientationLock: UIInterfaceOrientationMask = .portrait

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        if UIDevice.current.userInterfaceIdiom == .phone {
            return Self.orientationLock
        }
        return .all
    }

    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        AppLogger.info("AppDelegate received handleEventsForBackgroundURLSession: \(identifier)")
        DownloadManager.shared.handleEventsForBackgroundURLSession(identifier: identifier, completionHandler: completionHandler)
    }
}

enum OrientationHelper {
    static func lockOrientation(_ orientation: UIInterfaceOrientationMask, rotateTo: UIInterfaceOrientation? = nil) {
        guard UIDevice.current.userInterfaceIdiom == .phone else {
            // iPad, Mac Catalyst, and tvOS allow freeform orientation and windowing
            return
        }

        AppDelegate.orientationLock = orientation

        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let windowScene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first else {
            return
        }

        let keyWindow = windowScene.windows.first(where: { $0.isKeyWindow }) ?? windowScene.keyWindow
        keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()

        if let rotateTo {
            let geometryOrientation: UIInterfaceOrientationMask
            switch rotateTo {
            case .landscapeLeft:
                geometryOrientation = .landscapeLeft
            case .landscapeRight:
                geometryOrientation = .landscapeRight
            case .portraitUpsideDown:
                geometryOrientation = .portraitUpsideDown
            default:
                geometryOrientation = .portrait
            }
            windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: geometryOrientation)) { error in
                AppLogger.debug("Geometry update info: \(error.localizedDescription)")
            }
        } else {
            windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: orientation)) { _ in }
        }
    }
}
#endif

@main
struct JellyBoiApp: App {

    #if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif

    @State private var viewManager = ViewManager.shared
    @State private var serverViewModel = ServerViewModel.shared
    @State private var libraryViewModel = LibraryViewModel.shared
    @State private var playbackManager = PlaybackManager.shared
    @State private var downloadManager = DownloadManager.shared
    @State private var networkMonitor = NetworkMonitor.shared
    @State private var preferences = AppPreferences.shared

    init() {
        #if os(iOS)
        UISwitch.appearance().onTintColor = .systemGreen
        #endif
        AppLogRecorder.shared.start()
        StatusOverlayKit.defaultLoadingIndicator = {
            AnyView(JellyBoiLoadingIndicator())
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .statusOverlayLoadingIndicator {
                    JellyBoiLoadingIndicator()
                }
                .environment(viewManager)
                .environment(serverViewModel)
                .environment(libraryViewModel)
                .environment(playbackManager)
                .environment(downloadManager)
                .environment(networkMonitor)
                .environment(preferences)
                .toggleStyle(SwitchToggleStyle(tint: .green))
        }
    }
}
