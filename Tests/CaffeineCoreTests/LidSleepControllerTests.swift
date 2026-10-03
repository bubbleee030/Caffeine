//
//  LidSleepControllerTests.swift
//  CaffeineCoreTests
//

import XCTest
@testable import CaffeineCore

@MainActor
final class LidSleepControllerTests: XCTestCase {
    private var settings: FakeSleepSettings!
    private var authenticator: FakeAuthenticator!
    private var battery: FakeBattery!
    private var defaults: UserDefaults!
    private var controller: LidSleepController!

    private var flag: Bool {
        self.defaults.bool(forKey: LidSleepController.overrideFlagKey)
    }

    override func setUp() async throws {
        let suite = "LidSleepControllerTests-\(UUID().uuidString)"
        self.defaults = UserDefaults(suiteName: suite)
        self.addTeardownBlock { UserDefaults().removePersistentDomain(forName: suite) }
        self.settings = FakeSleepSettings()
        self.authenticator = FakeAuthenticator()
        self.battery = FakeBattery()
        self.controller = LidSleepController(
            settings: self.settings,
            authenticator: self.authenticator,
            battery: self.battery,
            defaults: self.defaults
        )
    }

    private func engage() async {
        self.controller.requestEngage()
        await self.controller.waitUntilIdle()
    }

    private func restore() async {
        self.controller.requestRestore()
        await self.controller.waitUntilIdle()
    }

    // MARK: - Engage

    func testEngageAuthenticatesThenDisablesSleep() async {
        await self.engage()

        XCTAssertEqual(self.controller.state, .on)
        XCTAssertNil(self.controller.lastFailure)
        XCTAssertEqual(self.settings.sleepDisabled, true)
        XCTAssertEqual(self.authenticator.reasons.count, 1)
        XCTAssertTrue(self.flag)
    }

    func testEngagePersistsFlagBeforeDisablingSleep() async {
        var flagWhenDisabling: Bool?
        self.settings.onSetSleepDisabled = { [unowned self] disabled in
            if disabled {
                flagWhenDisabling = self.flag
            }
        }

        await self.engage()

        XCTAssertEqual(flagWhenDisabling, true)
    }

    func testDeniedAuthenticationLeavesSleepAlone() async {
        self.authenticator.approve = false

        await self.engage()

        XCTAssertEqual(self.controller.state, .off)
        XCTAssertEqual(self.controller.lastFailure, .authenticationDenied)
        XCTAssertEqual(self.settings.calls, [])
        XCTAssertFalse(self.flag)
    }

    func testMissingRuleIsConfirmedAndInstalledBeforeEnabling() async {
        self.settings.isPasswordlessRuleInstalled = false
        var confirmations = 0
        self.controller.confirmSetup = {
            confirmations += 1
            return true
        }

        await self.engage()

        XCTAssertEqual(confirmations, 1)
        XCTAssertEqual(self.settings.calls, ["install", "set(true)"])
        XCTAssertEqual(self.controller.state, .on)
    }

    func testDeclinedSetupInstallsNothing() async {
        self.settings.isPasswordlessRuleInstalled = false
        self.controller.confirmSetup = { false }

        await self.engage()

        XCTAssertEqual(self.settings.calls, [])
        XCTAssertEqual(self.authenticator.reasons, [])
        XCTAssertEqual(self.controller.state, .off)
        XCTAssertEqual(self.controller.lastFailure, .setupFailed)
    }

    func testFailedInstallReportsSetupFailed() async {
        self.settings.isPasswordlessRuleInstalled = false
        self.settings.installError = TestError()

        await self.engage()

        XCTAssertEqual(self.settings.calls, ["install"])
        XCTAssertEqual(self.controller.state, .off)
        XCTAssertEqual(self.controller.lastFailure, .setupFailed)
    }

    func testFailedCommandRollsBackAndClearsFlag() async {
        self.settings.enableError = TestError()

        await self.engage()

        XCTAssertEqual(self.settings.calls, ["set(true)", "set(false)"])
        XCTAssertEqual(self.controller.state, .off)
        XCTAssertEqual(self.controller.lastFailure, .commandFailed)
        XCTAssertFalse(self.flag)
    }

    func testEngageRefusedOnLowBattery() async {
        self.battery.snapshot = PowerSnapshot(isOnBattery: true, percent: 15)

        await self.engage()

        XCTAssertEqual(self.authenticator.reasons, [])
        XCTAssertEqual(self.settings.calls, [])
        XCTAssertEqual(self.controller.lastFailure, .lowBattery)
    }

    func testLowPercentOnACDoesNotBlockEngage() async {
        self.battery.snapshot = PowerSnapshot(isOnBattery: false, percent: 5)

        await self.engage()

        XCTAssertEqual(self.controller.state, .on)
    }

    func testThresholdComesFromDefaults() async {
        self.defaults.set(50, forKey: LidSleepController.batteryThresholdKey)
        self.battery.snapshot = PowerSnapshot(isOnBattery: true, percent: 45)

        await self.engage()

        XCTAssertEqual(self.controller.batteryThreshold, 50)
        XCTAssertEqual(self.controller.lastFailure, .lowBattery)
    }

    // MARK: - Restore

    func testRestoreReEnablesSleepAndClearsFlag() async {
        await self.engage()

        await self.restore()

        XCTAssertEqual(self.settings.sleepDisabled, false)
        XCTAssertEqual(self.controller.state, .off)
        XCTAssertFalse(self.flag)
    }

    func testRestoreWithoutEngageDoesNothing() async {
        await self.restore()

        XCTAssertEqual(self.settings.calls, [])
    }

    func testFailedRestoreKeepsFlagForNextLaunch() async {
        await self.engage()
        self.settings.disableError = TestError()

        await self.restore()

        XCTAssertTrue(self.flag)
        XCTAssertEqual(self.controller.state, .off)
    }

    func testRestoreImmediatelyUsesBlockingCall() async {
        await self.engage()

        self.controller.restoreImmediately()

        XCTAssertEqual(self.settings.calls.last, "setNow(false)")
        XCTAssertEqual(self.settings.sleepDisabled, false)
        XCTAssertFalse(self.flag)
        XCTAssertEqual(self.controller.state, .off)
    }

    // MARK: - Launch recovery

    func testRecoveryRestoresOverrideLeftByCrash() async {
        self.defaults.set(true, forKey: LidSleepController.overrideFlagKey)
        self.settings.sleepDisabled = true

        await self.controller.recoverOnLaunch()

        XCTAssertEqual(self.settings.calls, ["read", "set(false)"])
        XCTAssertFalse(self.flag)
    }

    func testRecoveryClearsStaleFlag() async {
        self.defaults.set(true, forKey: LidSleepController.overrideFlagKey)
        self.settings.sleepDisabled = false

        await self.controller.recoverOnLaunch()

        XCTAssertEqual(self.settings.calls, ["read"])
        XCTAssertFalse(self.flag)
    }

    func testRecoveryIgnoresOverrideCaffeineDidNotSet() async {
        self.settings.sleepDisabled = true

        await self.controller.recoverOnLaunch()

        XCTAssertEqual(self.settings.calls, [])
        XCTAssertEqual(self.settings.sleepDisabled, true)
    }

    // MARK: - Battery guard

    func testLowBatteryWhileOnRestoresAndSleepsIfLidClosed() async {
        await self.engage()
        self.battery.snapshot = PowerSnapshot(isOnBattery: true, percent: 19)
        self.battery.isLidClosed = true

        self.battery.onChange?()
        await self.controller.waitUntilIdle()

        XCTAssertEqual(self.settings.sleepDisabled, false)
        XCTAssertEqual(self.controller.state, .off)
        XCTAssertEqual(self.controller.lastFailure, .lowBattery)
        XCTAssertEqual(self.battery.sleepNowCalls, 1)
    }

    func testLowBatteryWithLidOpenDoesNotForceSleep() async {
        await self.engage()
        self.battery.snapshot = PowerSnapshot(isOnBattery: true, percent: 10)

        self.battery.onChange?()
        await self.controller.waitUntilIdle()

        XCTAssertEqual(self.settings.sleepDisabled, false)
        XCTAssertEqual(self.battery.sleepNowCalls, 0)
    }

    func testBatteryAtThresholdKeepsClosedLidMode() async {
        await self.engage()
        self.battery.snapshot = PowerSnapshot(isOnBattery: true, percent: 20)

        self.battery.onChange?()
        await self.controller.waitUntilIdle()

        XCTAssertEqual(self.controller.state, .on)
        XCTAssertEqual(self.settings.sleepDisabled, true)
    }

    func testLowBatteryInClamshellWithDisplayStillSleeps() async {
        await self.engage()
        self.battery.snapshot = PowerSnapshot(isOnBattery: true, percent: 5)
        self.battery.isLidClosed = true
        self.battery.hasExternalDisplay = true

        self.battery.onChange?()
        await self.controller.waitUntilIdle()

        XCTAssertEqual(self.battery.sleepNowCalls, 1)
    }

    func testBatteryDroppingDuringAuthenticationRestoresAfterEngage() async {
        self.authenticator.onAuthenticate = { [unowned self] in
            self.battery.snapshot = PowerSnapshot(isOnBattery: true, percent: 10)
        }

        await self.engage()

        XCTAssertEqual(self.settings.calls, ["set(true)", "set(false)"])
        XCTAssertEqual(self.controller.state, .off)
        XCTAssertEqual(self.controller.lastFailure, .lowBattery)
    }

    func testRaisingThresholdAppliesImmediately() async {
        self.battery.snapshot = PowerSnapshot(isOnBattery: true, percent: 40)
        await self.engage()
        self.defaults.set(50, forKey: LidSleepController.batteryThresholdKey)

        self.controller.batteryThresholdDidChange()
        await self.controller.waitUntilIdle()

        XCTAssertEqual(self.controller.state, .off)
        XCTAssertEqual(self.controller.lastFailure, .lowBattery)
    }

    // MARK: - Sleep after restore

    func testRestoreSleepsWhenLidClosedWithoutExternalDisplay() async {
        await self.engage()
        self.battery.isLidClosed = true
        self.battery.hasExternalDisplay = false

        await self.restore()

        XCTAssertEqual(self.battery.sleepNowCalls, 1)
    }

    func testRestoreDoesNotSleepInClamshellWithExternalDisplay() async {
        await self.engage()
        self.battery.isLidClosed = true
        self.battery.hasExternalDisplay = true

        await self.restore()

        XCTAssertEqual(self.battery.sleepNowCalls, 0)
    }

    func testRestoreDoesNotSleepWithLidOpen() async {
        await self.engage()

        await self.restore()

        XCTAssertEqual(self.battery.sleepNowCalls, 0)
    }

    // MARK: - Display with the lid closed

    func testClosingLidWhileOnTurnsDisplayOff() async {
        await self.engage()
        self.battery.isLidClosed = true

        self.battery.onLidChange?()

        XCTAssertEqual(self.battery.displayOffCalls, 1)
    }

    func testClosingLidWithExternalDisplayKeepsDisplaysOn() async {
        await self.engage()
        self.battery.isLidClosed = true
        self.battery.hasExternalDisplay = true

        self.battery.onLidChange?()

        XCTAssertEqual(self.battery.displayOffCalls, 0)
    }

    func testClosingLidWhileOffDoesNothing() {
        self.battery.isLidClosed = true

        self.battery.onLidChange?()

        XCTAssertEqual(self.battery.displayOffCalls, 0)
    }

    func testOpeningLidDoesNothing() async {
        await self.engage()

        self.battery.onLidChange?()

        XCTAssertEqual(self.battery.displayOffCalls, 0)
    }

    // MARK: - Failures

    func testFailedRestoreIsReported() async {
        await self.engage()
        self.settings.disableError = TestError()

        await self.restore()

        XCTAssertEqual(self.controller.lastFailure, .restoreFailed)
    }

    func testFailedLaunchRecoveryIsReported() async {
        self.defaults.set(true, forKey: LidSleepController.overrideFlagKey)
        self.settings.sleepDisabled = true
        self.settings.disableError = TestError()

        await self.controller.recoverOnLaunch()

        XCTAssertEqual(self.controller.lastFailure, .restoreFailed)
        XCTAssertTrue(self.flag)
    }

    func testRestoreClearsEarlierFailure() async {
        self.authenticator.approve = false
        await self.engage()
        XCTAssertEqual(self.controller.lastFailure, .authenticationDenied)

        await self.restore()

        XCTAssertNil(self.controller.lastFailure)
    }

    // MARK: - Cancel callback

    func testCancelledTouchIDCallsOnCancel() async {
        self.authenticator.approve = false
        var cancels = 0

        self.controller.requestEngage(onCancel: { cancels += 1 })
        await self.controller.waitUntilIdle()

        XCTAssertEqual(cancels, 1)
    }

    func testDeclinedSetupCallsOnCancel() async {
        self.settings.isPasswordlessRuleInstalled = false
        self.controller.confirmSetup = { false }
        var cancels = 0

        self.controller.requestEngage(onCancel: { cancels += 1 })
        await self.controller.waitUntilIdle()

        XCTAssertEqual(cancels, 1)
    }

    func testSuccessfulEngageDoesNotCallOnCancel() async {
        var cancels = 0

        self.controller.requestEngage(onCancel: { cancels += 1 })
        await self.controller.waitUntilIdle()

        XCTAssertEqual(cancels, 0)
        XCTAssertEqual(self.controller.state, .on)
    }

    func testLowBatteryRefusalDoesNotCallOnCancel() async {
        self.battery.snapshot = PowerSnapshot(isOnBattery: true, percent: 5)
        var cancels = 0

        self.controller.requestEngage(onCancel: { cancels += 1 })
        await self.controller.waitUntilIdle()

        XCTAssertEqual(cancels, 0)
    }

    func testRestoreDuringTouchIDDoesNotCallOnCancel() async {
        self.authenticator.onAuthenticate = { [unowned self] in
            self.controller.requestRestore()
        }
        var cancels = 0

        self.controller.requestEngage(onCancel: { cancels += 1 })
        await self.controller.waitUntilIdle()

        XCTAssertEqual(cancels, 0)
    }

    // MARK: - Request queue

    func testRestoreRequestedDuringAuthenticationCancelsEngage() async {
        self.authenticator.onAuthenticate = { [unowned self] in
            self.controller.requestRestore()
        }

        await self.engage()

        XCTAssertEqual(self.settings.calls, [])
        XCTAssertEqual(self.controller.state, .off)
        XCTAssertNil(self.controller.lastFailure)
        XCTAssertFalse(self.flag)
    }

    func testRestoreRequestedDuringSetupAlertSkipsInstall() async {
        self.settings.isPasswordlessRuleInstalled = false
        self.controller.confirmSetup = { [unowned self] in
            self.controller.requestRestore()
            return true
        }

        await self.engage()

        XCTAssertEqual(self.settings.calls, [])
        XCTAssertEqual(self.authenticator.reasons, [])
    }

    func testRecoveryRunsBeforeQueuedEngage() async {
        self.defaults.set(true, forKey: LidSleepController.overrideFlagKey)
        self.settings.sleepDisabled = true

        self.controller.requestRecovery()
        self.controller.requestEngage()
        await self.controller.waitUntilIdle()

        XCTAssertEqual(self.settings.calls, ["read", "set(false)", "set(true)"])
        XCTAssertEqual(self.controller.state, .on)
    }
}

// MARK: - Fakes

private struct TestError: Error {}

@MainActor
private final class FakeSleepSettings: SleepSettingBackend {
    var sleepDisabled: Bool? = false
    var isPasswordlessRuleInstalled = true
    var installError: (any Error)?
    var enableError: (any Error)?
    var disableError: (any Error)?
    var onSetSleepDisabled: ((Bool) -> Void)?
    private(set) var calls: [String] = []

    func isSleepDisabled() -> Bool? {
        self.calls.append("read")
        return self.sleepDisabled
    }

    func setSleepDisabled(_ disabled: Bool) async throws {
        try self.apply(disabled, label: "set")
    }

    func setSleepDisabledImmediately(_ disabled: Bool) throws {
        try self.apply(disabled, label: "setNow")
    }

    func installPasswordlessRule() async throws {
        self.calls.append("install")
        if let installError {
            throw installError
        }
        self.isPasswordlessRuleInstalled = true
    }

    private func apply(_ disabled: Bool, label: String) throws {
        self.calls.append("\(label)(\(disabled))")
        self.onSetSleepDisabled?(disabled)
        if let error = disabled ? self.enableError : self.disableError {
            throw error
        }
        self.sleepDisabled = disabled
    }
}

@MainActor
private final class FakeAuthenticator: UserAuthenticator {
    var approve = true
    var onAuthenticate: (() -> Void)?
    private(set) var reasons: [String] = []

    func authenticate(reason: String) async -> Bool {
        self.reasons.append(reason)
        self.onAuthenticate?()
        return self.approve
    }
}

@MainActor
private final class FakeBattery: BatteryMonitor {
    var snapshot = PowerSnapshot(isOnBattery: false, percent: 100)
    var isLidClosed = false
    var hasExternalDisplay = false
    var onChange: (() -> Void)?
    var onLidChange: (() -> Void)?
    private(set) var sleepNowCalls = 0
    private(set) var displayOffCalls = 0

    func sleepNow() {
        self.sleepNowCalls += 1
    }

    func turnDisplayOff() {
        self.displayOffCalls += 1
    }
}
