//
//  LidSleepController.swift
//  Caffeine
//

#if canImport(DZFoundation)
import DZFoundation
#endif
import Foundation
import Observation

/// Keeps a portable Mac running with the lid closed — on battery too — by
/// switching the system-wide `SleepDisabled` power setting
/// (`pmset disablesleep`) while a Caffeine session is active.
///
/// `SleepDisabled` survives quits, crashes and reboots, so the controller
/// persists ``overrideFlagKey`` *before* switching it on and restores it on
/// every exit path: deactivation, quit (``restoreImmediately()``), low
/// battery, and the next launch (``requestRecovery()``). A `SleepDisabled`
/// that Caffeine didn't set is never touched.
///
/// Requests are serialized: each `request…` call runs after the previous one
/// finished, so a restore can't overtake an engage still waiting for Touch ID.
/// A restore requested meanwhile also cancels that engage at its next step, so
/// the user isn't asked to confirm a session they already ended.
@MainActor
@Observable
public final class LidSleepController {
    public enum State: Equatable, Sendable {
        case off
        case enabling
        case on
        case restoring
    }

    public enum Failure: Equatable, Sendable {
        /// The one-time administrator setup was declined or failed.
        case setupFailed
        /// Touch ID / password confirmation was cancelled or failed.
        case authenticationDenied
        /// `pmset disablesleep 1` failed.
        case commandFailed
        /// On battery below ``batteryThreshold``.
        case lowBattery
        /// `pmset disablesleep 0` failed; sleep may still be disabled.
        case restoreFailed
    }

    enum RestoreReason {
        /// Deactivation, timer end or toggle off.
        case user
        /// Battery fell below ``batteryThreshold``.
        case lowBattery
    }

    public static let overrideFlagKey = "CALidSleepOverrideActive"
    public static let batteryThresholdKey = "CALidSleepBatteryThreshold"
    public static let defaultBatteryThreshold = 20

    public private(set) var state: State = .off
    public private(set) var lastFailure: Failure?

    /// Asked before the one-time administrator prompt; return `false` to
    /// cancel. The app replaces this with an explanatory alert.
    @ObservationIgnored
    public var confirmSetup: @MainActor () async -> Bool = { true }

    private let settings: any SleepSettingBackend
    private let authenticator: any UserAuthenticator
    private let battery: any BatteryMonitor
    private let defaults: UserDefaults
    @ObservationIgnored
    private var pending: Task<Void, Never>?
    /// Set by ``requestEngage()``, cleared by ``requestRestore()``: a queued
    /// engage stops as soon as it sees this is false.
    @ObservationIgnored
    private var wantsEngaged = false

    public init(
        settings: any SleepSettingBackend,
        authenticator: any UserAuthenticator,
        battery: any BatteryMonitor,
        defaults: UserDefaults = .standard
    ) {
        self.settings = settings
        self.authenticator = authenticator
        self.battery = battery
        self.defaults = defaults
        self.battery.onChange = { [weak self] in self?.batteryDidChange() }
    }

    /// Battery percentage below which closed-lid mode is turned off while
    /// running on battery.
    public var batteryThreshold: Int {
        let stored = self.defaults.integer(forKey: Self.batteryThresholdKey)
        return stored > 0 ? stored : Self.defaultBatteryThreshold
    }

    // MARK: - Requests (serialized)

    /// Restores sleep if a previous run crashed while closed-lid mode was on.
    public func requestRecovery() {
        self.enqueue { await $0.recoverOnLaunch() }
    }

    public func requestEngage() {
        self.wantsEngaged = true
        self.enqueue { await $0.engage() }
    }

    public func requestRestore() {
        self.wantsEngaged = false
        self.enqueue { await $0.restore(.user) }
    }

    /// Call when the threshold preference changes, so a battery already below
    /// the new value turns closed-lid mode off right away.
    public func batteryThresholdDidChange() {
        self.checkBattery()
    }

    /// Waits until every queued request has finished.
    public func waitUntilIdle() async {
        while let task = self.pending {
            await task.value
            if self.pending == task {
                self.pending = nil
            }
        }
    }

    /// Restores sleep synchronously. Call from `applicationWillTerminate`,
    /// where queued async work would never run.
    public func restoreImmediately() {
        self.wantsEngaged = false
        guard self.defaults.bool(forKey: Self.overrideFlagKey) else { return }
        do {
            try self.settings.setSleepDisabledImmediately(false)
            // While enabling, a `disablesleep 1` may still be in flight and
            // land after this call; keep the flag so the next launch checks.
            if self.state != .enabling {
                self.defaults.removeObject(forKey: Self.overrideFlagKey)
            }
        } catch {
            self.log(error)
        }
        self.state = .off
    }

    // MARK: - Operations

    func engage() async {
        guard self.state == .off, self.wantsEngaged else { return }
        self.lastFailure = nil
        guard !self.isBatteryLow else {
            self.lastFailure = .lowBattery
            return
        }
        self.state = .enabling

        if !self.settings.isPasswordlessRuleInstalled {
            guard await self.confirmSetup() else {
                self.fail(.setupFailed)
                return
            }
            guard self.wantsEngaged else {
                self.state = .off
                return
            }
            do {
                try await self.settings.installPasswordlessRule()
            } catch {
                self.log(error)
                self.fail(.setupFailed)
                return
            }
        }

        guard await self.authenticator.authenticate(reason: String(localized: "enable closed-lid mode")) else {
            self.fail(.authenticationDenied)
            return
        }
        guard self.wantsEngaged else {
            self.state = .off
            return
        }

        // Persist first: a crash during the call must not leave an
        // unrecorded system-wide override.
        self.defaults.set(true, forKey: Self.overrideFlagKey)
        do {
            try await self.settings.setSleepDisabled(true)
            self.state = .on
            // The battery may have dropped while waiting for Touch ID.
            self.checkBattery()
        } catch {
            self.log(error)
            let restored = await self.restoreSetting()
            self.fail(restored ? .commandFailed : .restoreFailed)
        }
    }

    func restore(_ reason: RestoreReason) async {
        if reason == .user {
            self.lastFailure = nil
        }
        guard self.defaults.bool(forKey: Self.overrideFlagKey) || self.state != .off else { return }
        self.state = .restoring
        let restored = await self.restoreSetting()
        self.state = .off
        guard restored else { return }
        if reason == .lowBattery {
            self.lastFailure = .lowBattery
        }

        // With the lid already shut, re-enabling sleep doesn't make macOS
        // sleep by itself (the lid-close event has passed). Put it to sleep,
        // unless an external display is in use (clamshell mode) and this
        // wasn't a low-battery stop.
        if self.battery.isLidClosed, reason == .lowBattery || !self.battery.hasActiveDisplay {
            self.battery.sleepNow()
        }
    }

    func recoverOnLaunch() async {
        guard self.defaults.bool(forKey: Self.overrideFlagKey) else { return }
        if self.settings.isSleepDisabled() == false {
            self.defaults.removeObject(forKey: Self.overrideFlagKey)
            return
        }
        await self.restoreSetting()
    }

    // MARK: - Private

    private var isBatteryLow: Bool {
        let snapshot = self.battery.snapshot
        guard snapshot.isOnBattery, let percent = snapshot.percent else { return false }
        return percent < self.batteryThreshold
    }

    private func batteryDidChange() {
        self.checkBattery()
    }

    private func checkBattery() {
        guard self.state == .on, self.isBatteryLow else { return }
        self.enqueue { await $0.restore(.lowBattery) }
    }

    /// Re-enables sleep. The flag is only cleared on success, so a failed
    /// restore is retried by the next launch's recovery; the failure is
    /// surfaced through ``lastFailure``.
    @discardableResult
    private func restoreSetting() async -> Bool {
        do {
            try await self.settings.setSleepDisabled(false)
            self.defaults.removeObject(forKey: Self.overrideFlagKey)
            return true
        } catch {
            self.log(error)
            self.lastFailure = .restoreFailed
            return false
        }
    }

    private func fail(_ failure: Failure) {
        self.lastFailure = failure
        self.state = .off
    }

    private func enqueue(_ operation: @escaping @MainActor (LidSleepController) async -> Void) {
        let previous = self.pending
        self.pending = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            await operation(self)
        }
    }

    private func log(_ error: any Error) {
        #if canImport(DZFoundation)
        DZErrorLog(error)
        #endif
    }
}
