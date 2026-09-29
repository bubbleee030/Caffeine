//
//  AppDelegate.swift
//  Caffeine
//
//  Created by Dominic Rodemer on 11.11.25.
//

import Cocoa
import Sparkle
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate, SPUStandardUserDriverDelegate {
    /// Make this lazy so `self` can be used safely
    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: self
    )
    private var menuBarController: MenuBarController?
    private var terminationSignalSource: DispatchSourceSignal?

    func applicationDidFinishLaunching(_: Notification) {
        // Create the menu bar controller
        self.menuBarController = MenuBarController(updaterController: self.updaterController)

        // Hide the dock icon - this is a menu bar only app
        NSApp.setActivationPolicy(.accessory)

        self.handleTerminationSignal()
    }

    func applicationWillTerminate(_: Notification) {
        // Clean up
        self.menuBarController?.cleanup()
    }

    /// `kill`/`killall` send SIGTERM, which ends the process without calling
    /// `applicationWillTerminate` — skipping cleanup such as restoring
    /// lid-close sleep. Route it through a normal termination instead.
    private func handleTerminationSignal() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler {
            MainActor.assumeIsolated {
                NSApp.terminate(nil)
            }
        }
        source.resume()
        self.terminationSignalSource = source
    }

    // MARK: - SPUStandardUserDriverDelegate

    func supportsGentleScheduledUpdateReminders() -> Bool {
        true
    }
}
