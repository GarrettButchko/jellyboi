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

#if os(iOS)
final class AppDelegate: NSObject, UIApplicationDelegate {
    static var orientationLock: UIInterfaceOrientationMask = .portrait

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        return Self.orientationLock
    }
}

enum OrientationHelper {
    static func lockOrientation(_ orientation: UIInterfaceOrientationMask, rotateTo: UIInterfaceOrientation? = nil) {
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
                AppLogger.debug("Geometry update info: \(error.localizedDescription)", tag: "Orientation")
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

    @StateObject private var viewManager = ViewManager()
    @State private var serverViewModel = ServerViewModel()
    @State private var libraryViewModel = LibraryViewModel()
    @State private var playbackManager = PlaybackManager.shared
    @State private var downloadManager = DownloadManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewManager)
                .environment(serverViewModel)
                .environment(libraryViewModel)
                .environment(playbackManager)
                .environment(downloadManager)
        }
    }
}
