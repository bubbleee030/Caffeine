//
//  LaunchAtLoginManager.swift
//  Caffeine
//

import Foundation
import Observation
import os

private let logger = Logger(subsystem: "net.domzilla.caffeine", category: "LaunchAtLoginManager")

/// Source of truth for the "Launch at Login" preference. The published
/// `isEnabled` value mirrors the underlying ``LaunchItemBackend``; user-driven
/// changes go through `setEnabled(_:)`. If the user toggles the login item via
/// System Settings instead of the app, call `refresh()` to re-read state.
@MainActor
@Observable
public final class LaunchAtLoginManager {
    public static let shared = LaunchAtLoginManager()

    public private(set) var isEnabled: Bool = false

    /// The error from the most recent `setEnabled(_:)` call, if any.
    /// Cleared on the next successful operation.
    public private(set) var lastError: (any Error)?

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
    ///
    /// On failure, the error is logged via `os.Logger` (visible in Console.app
    /// under subsystem `net.domzilla.caffeine`) and surfaced on ``lastError``
    /// so callers can present it to the user. ``refresh()`` is always called
    /// afterwards so the published `isEnabled` reflects the backend's truth —
    /// for a SwiftUI `Toggle` this means a failed register snaps the toggle
    /// back to off.
    @discardableResult
    public func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled, !self.backend.isEnabled {
                try self.backend.register()
            } else if !enabled, self.backend.isEnabled {
                try self.backend.unregister()
            }
            self.lastError = nil
            self.refresh()
            return true
        } catch {
            logger.error(
                "Failed to \(enabled ? "register" : "unregister", privacy: .public) login item: \(error.localizedDescription, privacy: .public)"
            )
            self.lastError = error
            self.refresh()
            return false
        }
    }
}
