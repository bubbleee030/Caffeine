//
//  CaffeineViewModel.swift
//  Caffeine
//
//  Created by Dominic Rodemer on 11.11.25.
//

import AppKit
import ApplicationServices
import Combine
import SwiftUI

/// Main view model for the Caffeine application
@MainActor
class CaffeineViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var isActive = false
    @Published var timeRemaining: TimeInterval?
    @Published var showPreferences = false

    // MARK: - Private Properties

    private var timeoutTimer: Timer?
    private var displayTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private let lidSleep = LidSleepController.shared

    // MARK: - Initialization

    init() {
        // Explicitly ensure we start inactive
        self.isActive = false
        self.timeRemaining = nil

        self.setupObservers()

        self.lidSleep.confirmSetup = { Self.confirmLidSleepSetup() }
        // Restore sleep if a previous run crashed with closed-lid mode on.
        // Queued before any activation below, so it always runs first.
        self.lidSleep.requestRecovery()

        #if DEBUG
        // Test hook: integration script sets CA_TEST_AUTOACTIVATE=lid-closed
        // (or any other value) to force activation on launch with a known
        // lid-close flag. Passes the value as an override so we don't write
        // to the persistent UserDefaults from a test env var. Intentional
        // early return so we don't pop the preferences window during a
        // headless integration run — add future init above this guard, not
        // below it. Compiled out in Release.
        if TestHook.autoActivateMode != nil {
            self.activate(allowLidCloseOverride: TestHook.allowsLidClose)
            return
        }
        #endif

        // Check if we should activate at launch
        // Automatic activation never engages closed-lid mode on battery, so
        // logging in doesn't pop up a Touch ID prompt nobody asked for. The
        // AC lid-close assertion still applies.
        if UserDefaults.standard.bool(forKey: PreferenceKeys.activateAtLaunch) {
            self.activate(engagesLidSleep: false)
        }

        // Show preferences on first launch
        if !UserDefaults.standard.bool(forKey: PreferenceKeys.suppressLaunchMessage) {
            self.showPreferences = true
        }
    }

    // MARK: - Public Methods

    /// Toggles the active state
    func toggleActive() {
        if self.isActive {
            self.deactivate()
        } else {
            self.activate()
        }
    }

    /// Activates Caffeine with optional timeout.
    /// - Parameters:
    ///   - timeout: optional duration before auto-deactivation.
    ///   - allowLidCloseOverride: if non-nil, used instead of the stored
    ///     `allowLidClose` preference. Intended for DEBUG test hooks that
    ///     want to drive a known state without mutating UserDefaults.
    ///   - engagesLidSleep: `false` skips closed-lid mode on battery (and its
    ///     Touch ID prompt) for activations the user didn't trigger.
    func activate(
        withTimeout timeout: TimeInterval? = nil,
        allowLidCloseOverride: Bool? = nil,
        engagesLidSleep: Bool = true
    ) {
        // Use default duration if no timeout specified
        let duration: TimeInterval?
        if let timeout {
            duration = timeout > 0 ? timeout : nil
        } else {
            let defaultMinutes = UserDefaults.standard.integer(forKey: PreferenceKeys.defaultDuration)
            duration = defaultMinutes > 0 ? TimeInterval(defaultMinutes * 60) : nil
        }

        // Cancel existing timers
        self.cancelTimers()

        // Set up timeout timer if duration specified
        if let duration {
            self.timeRemaining = duration

            self.timeoutTimer = Timer.scheduledTimer(
                withTimeInterval: duration,
                repeats: false
            ) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.deactivate()
                }
            }

            // Update display every second
            self.displayTimer = Timer.scheduledTimer(
                withTimeInterval: 1.0,
                repeats: true
            ) { [weak self] _ in
                DispatchQueue.main.async {
                    guard
                        let self,
                        let timeoutTimer = self.timeoutTimer else
                    {
                        self?.displayTimer?.invalidate()
                        return
                    }

                    self.timeRemaining = max(0, timeoutTimer.fireDate.timeIntervalSinceNow)
                    if self.timeRemaining ?? 0 <= 0 {
                        self.displayTimer?.invalidate()
                        self.displayTimer = nil
                    }
                }
            }
        } else {
            self.timeRemaining = nil
        }

        self.isActive = true
        let allowLidClose = allowLidCloseOverride
            ?? UserDefaults.standard.bool(forKey: PreferenceKeys.allowLidClose)
        SleepPreventionManager.shared.preventSleep(allowLidClose: allowLidClose)
        if allowLidClose, engagesLidSleep, self.shouldEngageLidSleep {
            self.lidSleep.requestEngage()
        }

        if UserDefaults.standard.bool(forKey: PreferenceKeys.keepAppsActive) {
            ActivitySimulator.shared.startMonitoring()
        }
    }

    /// Whether "Allow Mac to run with lid closed" is on.
    var allowsLidClose: Bool {
        UserDefaults.standard.bool(forKey: PreferenceKeys.allowLidClose)
    }

    /// Menu shortcut for the Preferences checkbox: persists the flipped value
    /// (PreferencesView's `@AppStorage` picks it up), then applies it.
    func toggleAllowLidClose() {
        let enabled = !self.allowsLidClose
        UserDefaults.standard.set(enabled, forKey: PreferenceKeys.allowLidClose)
        self.setAllowLidClose(enabled)
    }

    /// Applies the lid-close flag to the active sleep-prevention manager.
    /// Doesn't persist it: PreferencesView's `@AppStorage` binding and
    /// ``toggleAllowLidClose()`` do.
    func setAllowLidClose(_ enabled: Bool) {
        SleepPreventionManager.shared.updateAllowLidClose(enabled)
        if !enabled {
            self.lidSleep.requestRestore()
        } else if self.isActive, self.shouldEngageLidSleep {
            self.lidSleep.requestEngage()
        }
    }

    /// Deactivates Caffeine
    func deactivate() {
        self.cancelTimers()
        self.timeRemaining = nil
        self.isActive = false
        SleepPreventionManager.shared.allowSleep()
        self.lidSleep.requestRestore()
        ActivitySimulator.shared.stopMonitoring()
    }

    /// Updates activity simulation based on preference
    func updateActivitySimulation(enabled: Bool) {
        if enabled {
            // Trigger the Accessibility permission prompt by posting a no-op event
            // This prompts for "Events" permission which CGEvent.post requires
            ActivitySimulator.shared.requestPermission()
        }

        if enabled, self.isActive {
            ActivitySimulator.shared.startMonitoring()
        } else {
            ActivitySimulator.shared.stopMonitoring()
        }
    }

    /// Returns a formatted string for the remaining time
    func formattedTimeRemaining() -> String? {
        // Only return a status if actually active
        guard self.isActive else {
            return nil
        }

        // If there's time remaining, format it
        if let remaining = timeRemaining, remaining > 0 {
            let seconds = Int(remaining)

            if seconds >= 3600 {
                let hours = seconds / 3600
                let minutes = (seconds % 3600) / 60
                return String(format: "%02d:%02d", hours, minutes)
            } else if seconds > 60 {
                let minutes = seconds / 60
                let format = String(localized: "%d minutes", comment: "Time remaining in minutes")
                return String.localizedStringWithFormat(format, minutes)
            } else {
                let format = String(localized: "%d seconds", comment: "Time remaining in seconds")
                return String.localizedStringWithFormat(format, seconds)
            }
        }

        // Active with no timer (indefinite)
        return String(localized: "Caffeine is active")
    }

    // MARK: - Private Methods

    /// Integration runs other than `lid-battery` must never trigger the
    /// administrator or Touch ID prompts.
    private var shouldEngageLidSleep: Bool {
        #if DEBUG
        if TestHook.autoActivateMode != nil {
            return TestHook.engagesLidSleep
        }
        #endif
        return true
    }

    /// Explains the one-time administrator prompt before it appears.
    private static func confirmLidSleepSetup() -> Bool {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = String(localized: "Allow closed-lid mode on battery?")
        alert.informativeText = String(
            localized: "Caffeine will ask for your administrator password once to install a rule that only lets it turn lid-close sleep on and off. You can remove the rule at any time in Terminal with:\nsudo rm /etc/sudoers.d/caffeine-lid"
        )
        alert.addButton(withTitle: String(localized: "Continue"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func setupObservers() {
        // Observe workspace sleep notification
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    if UserDefaults.standard.bool(forKey: PreferenceKeys.deactivateOnManualSleep) {
                        self?.deactivate()
                    }
                }
            }
            .store(in: &self.cancellables)

        // Run-loop timers don't advance during sleep, so on wake check whether
        // the activation period elapsed and deactivate if so
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    guard let self, let timeoutTimer = self.timeoutTimer else { return }
                    if timeoutTimer.fireDate.timeIntervalSinceNow <= 0 {
                        self.deactivate()
                    }
                }
            }
            .store(in: &self.cancellables)
    }

    private func cancelTimers() {
        self.timeoutTimer?.invalidate()
        self.timeoutTimer = nil
        self.displayTimer?.invalidate()
        self.displayTimer = nil
    }
}

// MARK: - Preference Keys

enum PreferenceKeys {
    static let activateAtLaunch = "CAActivateAtLaunch"
    static let defaultDuration = "CADefaultDuration"
    static let suppressLaunchMessage = "CASuppressLaunchMessage"
    static let deactivateOnManualSleep = "CADeactivateOnManualSleep"
    static let keepAppsActive = "CAKeepAppsActive"
    static let allowLidClose = "CAAllowLidClose"
    static let lidSleepBatteryThreshold = LidSleepController.batteryThresholdKey
}
