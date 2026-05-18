//
//  PowerAssertionBackend.swift
//  Caffeine
//

import Foundation
import IOKit.pwr_mgt

/// Abstraction over the `IOPMAssertion` C API. Production uses
/// ``IOKitPowerAssertionBackend``; tests inject a recorder so they can assert
/// on the (type, reason) tuples that were requested.
public protocol PowerAssertionBackend: AnyObject {
    /// Creates an assertion of `type` with `reason` and the given `timeout`
    /// seconds. Returns the assertion ID on success, or `nil` if the kernel
    /// rejected the request.
    func create(type: String, reason: String, timeout: TimeInterval) -> UInt32?
    /// Releases a previously-created assertion. No-op if `id` was never created.
    func release(_ id: UInt32)
}

/// Default backend backed by `IOPMAssertionCreateWithDescription` /
/// `IOPMAssertionRelease`. Stateless — safe to share across actors.
public final class IOKitPowerAssertionBackend: PowerAssertionBackend, Sendable {
    public static let shared = IOKitPowerAssertionBackend()

    public init() {}

    public func create(type: String, reason: String, timeout: TimeInterval) -> UInt32? {
        var id: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithDescription(
            type as CFString,
            reason as CFString,
            nil,
            nil,
            nil,
            timeout,
            nil,
            &id
        )
        return result == kIOReturnSuccess ? id : nil
    }

    public func release(_ id: UInt32) {
        IOPMAssertionRelease(id)
    }
}
