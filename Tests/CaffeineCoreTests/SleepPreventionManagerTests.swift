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

    func testSessionResignReleasesHeldAssertionsImmediately() {
        // Without this behaviour, the kernel times the assertions out 30 s
        // later and the manager's stored IDs drift out of sync with reality.
        let fake = FakePowerAssertionBackend()
        let manager = SleepPreventionManager(backend: fake)
        manager.preventSleep(allowLidClose: true)
        XCTAssertEqual(manager.heldAssertionCount, 3)

        manager.handleSessionResignActive()

        XCTAssertEqual(
            manager.heldAssertionCount,
            0,
            "Resign-active must release immediately, not wait for the kernel timeout."
        )
        XCTAssertEqual(fake.releaseCalls.count, 3)
        XCTAssertTrue(fake.liveAssertions.isEmpty)
    }

    func testSessionBecomeActiveReengagesIfActive() {
        let fake = FakePowerAssertionBackend()
        let manager = SleepPreventionManager(backend: fake)
        manager.preventSleep(allowLidClose: true)
        manager.handleSessionResignActive()
        XCTAssertEqual(manager.heldAssertionCount, 0)

        manager.handleSessionBecomeActive()

        XCTAssertEqual(
            manager.heldAssertionCount,
            3,
            "Become-active should re-engage immediately, not wait up to 10 s for the next timer tick."
        )
    }

    func testSessionBecomeActiveDoesNothingIfNotActive() {
        let fake = FakePowerAssertionBackend()
        let manager = SleepPreventionManager(backend: fake)
        manager.handleSessionResignActive()
        manager.handleSessionBecomeActive()

        XCTAssertEqual(
            manager.heldAssertionCount,
            0,
            "Session events must not create assertions when the user hasn't activated Caffeine."
        )
    }

    func testManagerDeallocatesWhenOutOfScope() {
        // A selector-based NSWorkspace observer retains its target, which
        // would keep the manager alive forever and leak across tests. With
        // Combine + AnyCancellable, dropping the manager must drop the
        // observers too, and weakRef must become nil.
        weak var weakRef: SleepPreventionManager?
        do {
            let fake = FakePowerAssertionBackend()
            let manager = SleepPreventionManager(backend: fake)
            weakRef = manager
            XCTAssertNotNil(weakRef)
        }
        XCTAssertNil(weakRef, "Manager leaked — NSWorkspace observers are still retaining it.")
    }

    func testRefreshCreatesNewAssertionsBeforeReleasingOld() {
        // A release-then-create implementation leaves a microsecond gap with
        // zero held assertions; the contract is swap-then-release so the
        // kernel always sees at least one of each type during a refresh.
        let fake = FakePowerAssertionBackend()
        let manager = SleepPreventionManager(backend: fake)
        manager.preventSleep(allowLidClose: false)
        fake.operationLog.removeAll()

        manager.updateAllowLidClose(true)

        guard let firstRelease = fake.operationLog.firstIndex(where: { $0.kind == .release }) else {
            XCTFail("expected at least one release during refresh")
            return
        }
        let createsBeforeFirstRelease = fake.operationLog[..<firstRelease].filter { $0.kind == .create }.count
        XCTAssertEqual(
            createsBeforeFirstRelease, 3,
            "All 3 new assertions must be created before any old one is released."
        )
    }
}

// MARK: - Test doubles

enum FakeOperationKind { case create, release }
struct FakeOperation { let kind: FakeOperationKind
    let id: UInt32
    let type: String
}

private final class FakePowerAssertionBackend: PowerAssertionBackend, @unchecked Sendable {
    private var nextID: UInt32 = 1
    private(set) var liveAssertions: [UInt32: String] = [:]
    private(set) var createCalls: [(type: String, reason: String, timeout: TimeInterval)] = []
    private(set) var releaseCalls: [UInt32] = []
    var operationLog: [FakeOperation] = []

    func create(type: String, reason: String, timeout: TimeInterval) -> UInt32? {
        let id = self.nextID
        self.nextID += 1
        self.liveAssertions[id] = type
        self.createCalls.append((type, reason, timeout))
        self.operationLog.append(FakeOperation(kind: .create, id: id, type: type))
        return id
    }

    func release(_ id: UInt32) {
        let type = self.liveAssertions[id] ?? "unknown"
        self.releaseCalls.append(id)
        self.liveAssertions.removeValue(forKey: id)
        self.operationLog.append(FakeOperation(kind: .release, id: id, type: type))
    }
}
