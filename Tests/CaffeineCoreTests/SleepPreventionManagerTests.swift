//
//  SleepPreventionManagerTests.swift
//  CaffeineCoreTests
//

import XCTest
@testable import CaffeineCore

@MainActor
final class SleepPreventionManagerTests: XCTestCase {
    func testPreventSleepWithLidCloseFalseCreatesDisplayAndSystemIdleAssertions() {
        let fake = FakePowerAssertionBackend()
        let manager = SleepPreventionManager(backend: fake)

        manager.preventSleep(allowLidClose: false)

        XCTAssertEqual(manager.heldAssertionCount, 2)
        let liveTypes = Set(fake.liveAssertions.values)
        XCTAssertEqual(liveTypes, ["PreventUserIdleDisplaySleep", "PreventUserIdleSystemSleep"])
    }

    func testPreventSleepWithLidCloseTrueAddsPreventSystemAssertion() {
        let fake = FakePowerAssertionBackend()
        let manager = SleepPreventionManager(backend: fake)

        manager.preventSleep(allowLidClose: true)

        XCTAssertEqual(manager.heldAssertionCount, 3)
        let liveTypes = Set(fake.liveAssertions.values)
        XCTAssertEqual(
            liveTypes,
            ["PreventUserIdleDisplaySleep", "PreventUserIdleSystemSleep", "PreventSystemSleep"]
        )
    }

    func testUpdateAllowLidCloseTrueWhileActiveAddsThirdAssertion() {
        let fake = FakePowerAssertionBackend()
        let manager = SleepPreventionManager(backend: fake)
        manager.preventSleep(allowLidClose: false)
        XCTAssertEqual(manager.heldAssertionCount, 2)

        manager.updateAllowLidClose(true)

        XCTAssertEqual(manager.heldAssertionCount, 3)
        XCTAssertTrue(fake.liveAssertions.values.contains("PreventSystemSleep"))
    }

    func testUpdateAllowLidCloseFalseWhileActiveRemovesThirdAssertion() {
        let fake = FakePowerAssertionBackend()
        let manager = SleepPreventionManager(backend: fake)
        manager.preventSleep(allowLidClose: true)
        XCTAssertEqual(manager.heldAssertionCount, 3)

        manager.updateAllowLidClose(false)

        XCTAssertEqual(manager.heldAssertionCount, 2)
        XCTAssertFalse(fake.liveAssertions.values.contains("PreventSystemSleep"))
    }

    func testUpdateAllowLidCloseWhileInactiveDoesNotCreateAssertions() {
        let fake = FakePowerAssertionBackend()
        let manager = SleepPreventionManager(backend: fake)

        manager.updateAllowLidClose(true)

        XCTAssertEqual(manager.heldAssertionCount, 0)
        XCTAssertTrue(fake.liveAssertions.isEmpty)
    }

    func testAllowSleepReleasesAllAssertions() {
        let fake = FakePowerAssertionBackend()
        let manager = SleepPreventionManager(backend: fake)
        manager.preventSleep(allowLidClose: true)
        XCTAssertEqual(manager.heldAssertionCount, 3)

        manager.allowSleep()

        XCTAssertEqual(manager.heldAssertionCount, 0)
        XCTAssertTrue(fake.liveAssertions.isEmpty)
        XCTAssertEqual(fake.releaseCalls.count, 3)
    }

    func testAssertionTimeoutIsThirtySeconds() {
        let fake = FakePowerAssertionBackend()
        let manager = SleepPreventionManager(backend: fake)

        manager.preventSleep(allowLidClose: true)

        XCTAssertTrue(fake.createCalls.allSatisfy { $0.timeout == 30 })
    }
}

// MARK: - Test doubles

private final class FakePowerAssertionBackend: PowerAssertionBackend, @unchecked Sendable {
    private var nextID: UInt32 = 1
    private(set) var liveAssertions: [UInt32: String] = [:]
    private(set) var createCalls: [(type: String, reason: String, timeout: TimeInterval)] = []
    private(set) var releaseCalls: [UInt32] = []

    func create(type: String, reason: String, timeout: TimeInterval) -> UInt32? {
        let id = self.nextID
        self.nextID += 1
        self.liveAssertions[id] = type
        self.createCalls.append((type, reason, timeout))
        return id
    }

    func release(_ id: UInt32) {
        self.releaseCalls.append(id)
        self.liveAssertions.removeValue(forKey: id)
    }
}
