//
//  LaunchAtLoginManager.swift
//  Caffeine
//

import Foundation
import Observation

/// Source of truth for the "Launch at Login" preference. The published
/// `isEnabled` value mirrors the underlying ``LaunchItemBackend``; user-driven
/// changes go through `setEnabled(_:)`. If the user toggles the login item via
/// System Settings instead of the app, call `refresh()` to re-read state.
@MainActor
@Observable
public final class LaunchAtLoginManager {
    public static let shared = LaunchAtLoginManager()

    public private(set) var isEnabled: Bool = false

    private let backend: any LaunchItemBackend

    public init(backend: any LaunchItemBackend = SMAppServiceBackend.shared) {
        self.backend = backend
        self.refresh()
    }

    /// Re-reads the current state from the backend.
    public func refresh() {
        self.isEnabled = self.backend.isEnabled
    }

    /// Attempts to enable or disable the login item.
    /// - Returns: `true` if the backend call succeeded; `false` if it threw.
    @discardableResult
    public func setEnabled(_ enabled: Bool) -> Bool {
        let succeeded: Bool
        do {
            if enabled, !self.backend.isEnabled {
                try self.backend.register()
            } else if !enabled, self.backend.isEnabled {
                try self.backend.unregister()
            }
            succeeded = true
        } catch {
            succeeded = false
        }
        self.refresh()
        return succeeded
    }
}
