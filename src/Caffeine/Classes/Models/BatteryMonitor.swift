//
//  BatteryMonitor.swift
//  Caffeine
//

import Foundation
import IOKit.ps
import IOKit.pwr_mgt

public struct PowerSnapshot: Equatable, Sendable {
    public var isOnBattery: Bool
    /// Charge in percent; `nil` on Macs without a battery.
    public var percent: Int?

    public init(isOnBattery: Bool, percent: Int?) {
        self.isOnBattery = isOnBattery
        self.percent = percent
    }
}

/// Power source, lid state and system sleep. Production uses
/// ``IOKitBatteryMonitor``; tests inject a fake.
@MainActor
public protocol BatteryMonitor: AnyObject {
    var snapshot: PowerSnapshot { get }
    var isLidClosed: Bool { get }
    /// Called on the main thread whenever a power source changes.
    var onChange: (() -> Void)? { get set }
    /// Puts the Mac to sleep now.
    func sleepNow()
}

@MainActor
public final class IOKitBatteryMonitor: BatteryMonitor {
    public var onChange: (() -> Void)?

    /// `nonisolated(unsafe)` so `deinit` (nonisolated) can invalidate it; only
    /// written in `init`.
    private nonisolated(unsafe) var runLoopSource: CFRunLoopSource?

    public init() {
        // Unretained: the source is invalidated in deinit before self goes away.
        let context = Unmanaged.passUnretained(self).toOpaque()
        let source = IOPSNotificationCreateRunLoopSource({ context in
            // Pass the pointer as an integer: raw pointers aren't Sendable.
            guard let address = context.map({ UInt(bitPattern: $0) }) else { return }
            MainActor.assumeIsolated {
                guard let pointer = UnsafeMutableRawPointer(bitPattern: address) else { return }
                Unmanaged<IOKitBatteryMonitor>.fromOpaque(pointer).takeUnretainedValue().onChange?()
            }
        }, context)?.takeRetainedValue()

        if let source {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            self.runLoopSource = source
        }
    }

    deinit {
        if let runLoopSource {
            CFRunLoopSourceInvalidate(runLoopSource)
        }
    }

    public var snapshot: PowerSnapshot {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
            return PowerSnapshot(isOnBattery: false, percent: nil)
        }
        let providingType = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?
        let isOnBattery = providingType == kIOPSBatteryPowerValue

        let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] ?? []
        for source in sources {
            guard
                let description = IOPSGetPowerSourceDescription(info, source)?
                    .takeUnretainedValue() as? [String: Any],
                let current = description[kIOPSCurrentCapacityKey] as? Int,
                let max = description[kIOPSMaxCapacityKey] as? Int,
                max > 0 else { continue }
            return PowerSnapshot(isOnBattery: isOnBattery, percent: current * 100 / max)
        }
        return PowerSnapshot(isOnBattery: isOnBattery, percent: nil)
    }

    public var isLidClosed: Bool {
        RootDomain.boolProperty("AppleClamshellState") ?? false
    }

    public func sleepNow() {
        let port = IOPMFindPowerManagement(kIOMainPortDefault)
        guard port != 0 else { return }
        IOPMSleepSystem(port)
        IOServiceClose(port)
    }
}
