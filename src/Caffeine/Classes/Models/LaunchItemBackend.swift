//
//  LaunchItemBackend.swift
//  Caffeine
//

import Foundation
import ServiceManagement

/// Abstraction over the system login-item registration API. Production uses
/// ``SMAppServiceBackend``; tests inject a fake.
@MainActor
public protocol LaunchItemBackend: AnyObject {
    var isEnabled: Bool { get }
    func register() throws
    func unregister() throws
}

/// Default backend that registers the running app as a macOS login item via
/// `SMAppService.mainApp`. Sandbox-safe; requires macOS 13+.
@MainActor
public final class SMAppServiceBackend: LaunchItemBackend {
    public static let shared = SMAppServiceBackend()

    public init() {}

    public var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    public func register() throws {
        try SMAppService.mainApp.register()
    }

    public func unregister() throws {
        try SMAppService.mainApp.unregister()
    }
}
