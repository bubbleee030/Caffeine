//
//  PackageSmokeTests.swift
//  CaffeineCoreTests
//

import XCTest
@testable import CaffeineCore

final class PackageSmokeTests: XCTestCase {
    @MainActor
    func testLoginBackendSharedExists() {
        XCTAssertNotNil(SMAppServiceBackend.shared)
    }

    func testPowerBackendSharedExists() {
        XCTAssertNotNil(IOKitPowerAssertionBackend.shared)
    }

    @MainActor
    func testPmsetBackendReadsSleepDisabled() {
        XCTAssertNotNil(PmsetSleepSettingBackend().isSleepDisabled())
    }

    @MainActor
    func testBatteryMonitorReadsSnapshot() throws {
        let monitor = IOKitBatteryMonitor()
        let snapshot = monitor.snapshot

        // Desktops have no battery: percent is nil and never "on battery".
        if snapshot.percent == nil {
            XCTAssertFalse(snapshot.isOnBattery)
        } else {
            XCTAssertTrue(try (0...100).contains(XCTUnwrap(snapshot.percent)))
        }
        _ = monitor.isLidClosed
    }
}
