//
//  LaunchAtLoginManagerTests.swift
//  CaffeineCoreTests
//

import XCTest
@testable import CaffeineCore

@MainActor
final class LaunchAtLoginManagerTests: XCTestCase {
    func testSetEnabledTrueRegistersAndPublishes() {
        let backend = FakeLaunchItemBackend()
        let manager = LaunchAtLoginManager(backend: backend)

        let ok = manager.setEnabled(true)

        XCTAssertTrue(ok)
        XCTAssertEqual(backend.registerCalls, 1)
        XCTAssertEqual(backend.unregisterCalls, 0)
        XCTAssertTrue(manager.isEnabled)
    }

    func testSetEnabledFalseUnregistersAndPublishes() {
        let backend = FakeLaunchItemBackend()
        backend.isEnabled = true
        let manager = LaunchAtLoginManager(backend: backend)

        let ok = manager.setEnabled(false)

        XCTAssertTrue(ok)
        XCTAssertEqual(backend.unregisterCalls, 1)
        XCTAssertEqual(backend.registerCalls, 0)
        XCTAssertFalse(manager.isEnabled)
    }

    func testSetEnabledTrueWhenAlreadyEnabledIsNoop() {
        let backend = FakeLaunchItemBackend()
        backend.isEnabled = true
        let manager = LaunchAtLoginManager(backend: backend)

        _ = manager.setEnabled(true)

        XCTAssertEqual(backend.registerCalls, 0)
        XCTAssertTrue(manager.isEnabled)
    }

    func testSetEnabledReturnsFalseAndReflectsBackendWhenRegisterThrows() {
        let backend = FakeLaunchItemBackend()
        backend.registerError = FakeError.boom
        let manager = LaunchAtLoginManager(backend: backend)

        let ok = manager.setEnabled(true)

        XCTAssertFalse(ok)
        XCTAssertEqual(backend.registerCalls, 1)
        XCTAssertFalse(manager.isEnabled, "register threw, so backend state stayed false; manager must mirror.")
        XCTAssertNotNil(manager.lastError, "register threw; lastError must surface it for the UI to act on.")
    }

    func testSuccessClearsPreviousLastError() {
        let backend = FakeLaunchItemBackend()
        backend.registerError = FakeError.boom
        let manager = LaunchAtLoginManager(backend: backend)
        _ = manager.setEnabled(true)
        XCTAssertNotNil(manager.lastError)

        backend.registerError = nil
        _ = manager.setEnabled(true)

        XCTAssertNil(manager.lastError, "A subsequent successful call must clear the prior error.")
    }

    func testRefreshReadsBackendState() {
        let backend = FakeLaunchItemBackend()
        let manager = LaunchAtLoginManager(backend: backend)
        XCTAssertFalse(manager.isEnabled)

        backend.isEnabled = true
        manager.refresh()

        XCTAssertTrue(manager.isEnabled)
    }
}

// MARK: - Test doubles

@MainActor
private final class FakeLaunchItemBackend: LaunchItemBackend {
    var isEnabled: Bool = false
    private(set) var registerCalls = 0
    private(set) var unregisterCalls = 0
    var registerError: Error?
    var unregisterError: Error?

    func register() throws {
        self.registerCalls += 1
        if let registerError { throw registerError }
        self.isEnabled = true
    }

    func unregister() throws {
        self.unregisterCalls += 1
        if let unregisterError { throw unregisterError }
        self.isEnabled = false
    }
}

private enum FakeError: Error { case boom }
