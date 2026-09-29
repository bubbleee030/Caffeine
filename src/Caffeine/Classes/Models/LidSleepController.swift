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
        /// On battery at or below ``batteryThreshold``.
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

    /// Battery percentage at or below which closed-lid mode is turned off
    /// while running on battery.
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
        self.enqueue { await $0.engage() }
    }

    public func requestRestore() {
        self.enqueue { await $0.restore() }
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
        guard self.state == .off else { return }
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

        // Persist first: a crash during the call must not leave an
        // unrecorded system-wide override.
        self.defaults.set(true, forKey: Self.overrideFlagKey)
        do {
            try await self.settings.setSleepDisabled(true)
            self.state = .on
        } catch {
            self.log(error)
            await self.restoreSetting()
            self.fail(.commandFailed)
        }
    }

    func restore(sleepIfLidClosed: Bool = false) async {
        guard self.defaults.bool(forKey: Self.overrideFlagKey) || self.state != .off else { return }
        self.state = .restoring
        await self.restoreSetting()
        self.state = .off
        if sleepIfLidClosed, self.battery.isLidClosed {
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
        return percent <= self.batteryThreshold
    }

    private func batteryDidChange() {
        guard self.state == .on, self.isBatteryLow else { return }
        self.lastFailure = .lowBattery
        self.enqueue { await $0.restore(sleepIfLidClosed: true) }
    }

    /// Re-enables sleep. The flag is only cleared on success, so a failed
    /// restore is retried by the next launch's recovery.
    private func restoreSetting() async {
        do {
            try await self.settings.setSleepDisabled(false)
            self.defaults.removeObject(forKey: Self.overrideFlagKey)
        } catch {
            self.log(error)
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
