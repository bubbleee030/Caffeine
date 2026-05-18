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
}
