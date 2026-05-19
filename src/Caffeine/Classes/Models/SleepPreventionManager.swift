//
//  SleepPreventionManager.swift
//  Caffeine
//
//  Created by Dominic Rodemer on 11.11.25.
//

import AppKit
import Combine
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
    private var sessionObservers = Set<AnyCancellable>()

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
        let reason = String(localized: "Caffeine prevents sleep")

        // Swap-then-release: hold both old and new IDs briefly so the kernel
        // always sees at least one of each assertion type, even at the exact
        // moment of refresh. Releasing first would leave a microsecond gap.
        let newIdleDisplay = self.backend.create(
            type: kIOPMAssertPreventUserIdleDisplaySleep as String,
            reason: reason,
            timeout: 30
        )
        let newIdleSystem = self.backend.create(
            type: kIOPMAssertPreventUserIdleSystemSleep as String,
            reason: reason,
            timeout: 30
        )
        let newPreventSystem: UInt32? = self.allowLidClose
            ? self.backend.create(
                type: kIOPMAssertionTypePreventSystemSleep as String,
                reason: reason,
                timeout: 30
            )
            : nil

        let oldIdleDisplay = self.idleDisplayAssertionID
        let oldIdleSystem = self.idleSystemAssertionID
        let oldPreventSystem = self.preventSystemAssertionID

        self.idleDisplayAssertionID = newIdleDisplay
        self.idleSystemAssertionID = newIdleSystem
        self.preventSystemAssertionID = newPreventSystem

        if let id = oldIdleDisplay { self.backend.release(id) }
        if let id = oldIdleSystem { self.backend.release(id) }
        if let id = oldPreventSystem { self.backend.release(id) }
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
        // Publisher + AnyCancellable so the NSWorkspace observers are removed
        // automatically when the manager deallocates (test instances), matching
        // CaffeineViewModel's pattern. A selector-based observer would persist
        // forever because NotificationCenter retains its targets.
        let nc = NSWorkspace.shared.notificationCenter

        nc.publisher(for: NSWorkspace.sessionDidResignActiveNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in self?.handleSessionResignActive() }
            }
            .store(in: &self.sessionObservers)

        nc.publisher(for: NSWorkspace.sessionDidBecomeActiveNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in self?.handleSessionBecomeActive() }
            }
            .store(in: &self.sessionObservers)
    }

    /// Internal (not private) so tests can drive these directly without
    /// posting a real NSWorkspace notification and waiting for the Task
    /// @MainActor hop. Not part of the public API.
    func handleSessionResignActive() {
        self.isUserSessionActive = false
        // Release immediately so the manager's stored IDs match the kernel's
        // view of the world (the kernel will time them out anyway after 30 s).
        // Without this, `heldAssertionCount` lies during the inactive window
        // and re-engagement on resume waits up to 10 s for the next timer fire.
        self.releaseAll()
    }

    func handleSessionBecomeActive() {
        self.isUserSessionActive = true
        // Re-engage immediately on resume rather than waiting up to 10 s for
        // the timer's next tick.
        if self.isActive { self.refreshAssertions() }
    }
}
