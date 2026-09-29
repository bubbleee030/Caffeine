//
//  ActivitySimulator.swift
//  Caffeine
//
//  Created by Dominic Rodemer on 14.12.24.
//

import AppKit
import CoreGraphics
import Foundation
import IOKit

/// Simulates user activity when the system has been idle for too long.
/// This prevents apps like Microsoft Teams from showing "Away" status.
final class ActivitySimulator {
    static let shared = ActivitySimulator()

    private var checkTimer: Timer?
    private let idleThreshold: TimeInterval = 90 // seconds before simulating activity
    private let checkInterval: TimeInterval = 30 // how often to check idle time

    private init() {}

    // MARK: - Public Methods

    /// Starts monitoring system idle time and simulating activity when needed.
    /// The timer is scheduled synchronously so a `stopMonitoring()` issued right
    /// after this call always invalidates it (an async hop here used to let the
    /// timer be created *after* the stop, leaving simulation running).
    func startMonitoring() {
        self.stopMonitoring()

        self.checkTimer = Timer.scheduledTimer(
            withTimeInterval: self.checkInterval,
            repeats: true
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.checkAndSimulateIfNeeded()
            }
        }
    }

    /// Stops monitoring and simulating activity
    func stopMonitoring() {
        self.checkTimer?.invalidate()
        self.checkTimer = nil
    }

    /// Triggers the Accessibility permission prompt by posting a CGEvent
    func requestPermission() {
        self.simulateActivity()
    }

    // MARK: - Private Methods

    private func checkAndSimulateIfNeeded() {
        guard self.getSystemIdleTime() >= self.idleThreshold else { return }
        self.simulateActivity()
    }

    private func getSystemIdleTime() -> TimeInterval {
        var iterator: io_iterator_t = 0

        guard
            IOServiceGetMatchingServices(
                kIOMainPortDefault,
                IOServiceMatching("IOHIDSystem"),
                &iterator
            ) == KERN_SUCCESS else { return 0 }

        defer { IOObjectRelease(iterator) }

        let entry = IOIteratorNext(iterator)
        guard entry != 0 else { return 0 }

        defer { IOObjectRelease(entry) }

        var unmanagedDict: Unmanaged<CFMutableDictionary>?
        guard
            IORegistryEntryCreateCFProperties(
                entry,
                &unmanagedDict,
                kCFAllocatorDefault,
                0
            ) == KERN_SUCCESS,
            let dict = unmanagedDict?.takeRetainedValue() as? [String: Any],
            let idleTime = dict["HIDIdleTime"] as? Int64 else { return 0 }

        // HIDIdleTime is in nanoseconds
        return TimeInterval(idleTime) / 1_000_000_000
    }

    private func simulateActivity() {
        // Read the cursor position in CoreGraphics global coordinates (top-left
        // origin of the primary display). Flipping NSEvent.mouseLocation with
        // NSScreen.main's height was wrong on multi-display setups, because
        // NSScreen.main is the focused screen, not the primary one.
        guard let cgPoint = CGEvent(source: nil)?.location else { return }

        // CGEvent generates actual HID events that reset the system idle timer
        // CGWarpMouseCursorPosition does NOT reset HIDIdleTime as it bypasses HID
        if
            let moveEvent = CGEvent(
                mouseEventSource: nil,
                mouseType: .mouseMoved,
                mouseCursorPosition: cgPoint,
                mouseButton: .left
            )
        {
            moveEvent.post(tap: .cghidEventTap)
        }
    }
}
