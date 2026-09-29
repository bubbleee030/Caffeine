//
//  ProcessRunnerTests.swift
//  CaffeineCoreTests
//

import XCTest
@testable import CaffeineCore

final class ProcessRunnerTests: XCTestCase {
    func testCapturesOutputAndStatus() {
        let result = ProcessRunner.run("/bin/sh", ["-c", "echo hello; echo oops >&2; exit 3"])

        XCTAssertEqual(result.status, 3)
        XCTAssertTrue(result.output.contains("hello"))
        XCTAssertTrue(result.output.contains("oops"))
    }

    func testMissingExecutableReturnsMinusOne() {
        let result = ProcessRunner.run("/nonexistent/tool", [])

        XCTAssertEqual(result.status, -1)
    }

    func testTimeoutTerminatesAndReturnsMinusOne() {
        let start = Date()

        let result = ProcessRunner.run("/bin/sleep", ["5"], timeout: 0.5)

        XCTAssertEqual(result.status, -1)
        XCTAssertLessThan(Date().timeIntervalSince(start), 3)
    }
}

final class RootDomainTests: XCTestCase {
    func testReadsSleepDisabled() {
        XCTAssertNotNil(RootDomain.boolProperty("SleepDisabled"))
    }

    func testUnknownKeyIsNil() {
        XCTAssertNil(RootDomain.boolProperty("CaffeineDefinitelyNotAKey"))
    }
}
