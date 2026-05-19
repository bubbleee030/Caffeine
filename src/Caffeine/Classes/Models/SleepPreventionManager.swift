//
//  SleepPreventionManager.swift
//  Caffeine
//
//  Created by Dominic Rodemer on 11.11.25.
//

import AppKit
import Foundation
import IOKit.pwr_mgt

/// Manages the core functionality of preventing system sleep.
///
/// Holds up to three IOKit power assertions while active:
/// - `PreventUserIdleDisplaySleep` so the display does not dim from inactivity
/// - `PreventUserIdleSystemSleep` so the system does not idle-sleep
/// - `PreventSystemSleep` (only when the lid-close flag is on) so a portable
///   Mac on AC power stays running with the lid closed
///
/// The assertion timer refreshes every 10 s with a 30 s assertion timeout so
/// the windows always overlap (the previous 8 s timeout left a 2 s gap).
@MainActor
public final class SleepPreventionManager {
    public static let shared = SleepPreventionManager()

    private let backend: any PowerAssertionBackend

    private var idleDisplayAssertionID: UInt32?
    private var idleSystemAssertionID: UInt32?
    private var preventSystemAssertionID: UInt32?
    private var assertionTimer: Timer?
    private var isUserSessionActive = true
    private var allowLidClose = false
    private var isActive = false

    public init(backend: any PowerAssertionBackend = IOKitPowerAssertionBackend.shared) {
        self.backend = backend
        self.setupWorkspaceNotifications()
    }

    // MARK: - Public Methods

    /// Activates sleep prevention. Pass `allowLidClose: true` to also hold a
    /// `PreventSystemSleep` assertion so the Mac stays running with the lid
    /// closed (effective only on AC power).
    public func preventSleep(allowLidClose: Bool) {
        self.allowLidClose = allowLidClose
        self.isActive = true
        self.assertionTimer?.invalidate()
        self.assertionTimer = Timer.scheduledTimer(
            withTimeInterval: 10.0,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshAssertions() }
        }
        self.refreshAssertions()
    }

    /// Updates the lid-close flag while active so the change takes effect on
    /// the next refresh without re-activating from scratch. No-op when
    /// inactive.
    public func updateAllowLidClose(_ value: Bool) {
        guard self.allowLidClose != value else { return }
        self.allowLidClose = value
        if self.isActive { self.refreshAssertions() }
    }

    /// Allows the system to sleep normally and releases every held assertion.
    public func allowSleep() {
        self.assertionTimer?.invalidate()
        self.assertionTimer = nil
        self.isActive = false
        self.releaseAll()
    }

    // MARK: - Test introspection

    /// Number of assertions currently held by the manager. Exposed for tests.
    public var heldAssertionCount: Int {
        [self.idleDisplayAssertionID, self.idleSystemAssertionID, self.preventSystemAssertionID]
            .compactMap(\.self)
            .count
    }

    // MARK: - Private Methods

    private func refreshAssertions() {
        guard self.isUserSessionActive else { return }
        self.releaseAll()
        let reason = String(localized: "Caffeine prevents sleep")
        self.idleDisplayAssertionID = self.backend.create(
            type: kIOPMAssertPreventUserIdleDisplaySleep as String,
            reason: reason,
            timeout: 30
        )
        self.idleSystemAssertionID = self.backend.create(
            type: kIOPMAssertPreventUserIdleSystemSleep as String,
            reason: reason,
            timeout: 30
        )
        if self.allowLidClose {
            self.preventSystemAssertionID = self.backend.create(
                type: kIOPMAssertionTypePreventSystemSleep as String,
                reason: reason,
                timeout: 30
            )
        }
    }

    private func releaseAll() {
        if let id = idleDisplayAssertionID { self.backend.release(id) }
        if let id = idleSystemAssertionID { self.backend.release(id) }
        if let id = preventSystemAssertionID { self.backend.release(id) }
        self.idleDisplayAssertionID = nil
        self.idleSystemAssertionID = nil
        self.preventSystemAssertionID = nil
    }

    private func setupWorkspaceNotifications() {
        let nc = NSWorkspace.shared.notificationCenter

        nc.addObserver(
            self,
            selector: #selector(self.sessionDidResignActive),
            name: NSWorkspace.sessionDidResignActiveNotification,
            object: nil
        )

        nc.addObserver(
            self,
            selector: #selector(self.sessionDidBecomeActive),
            name: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil
        )
    }

    @objc
    private func sessionDidResignActive() {
        self.isUserSessionActive = false
    }

    @objc
    private func sessionDidBecomeActive() {
        self.isUserSessionActive = true
    }
}
