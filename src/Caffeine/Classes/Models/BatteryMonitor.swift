//
//  BatteryMonitor.swift
//  Caffeine
//

import CoreGraphics
import Foundation
import IOKit
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
    /// Whether a display other than the built-in panel is connected.
    var hasExternalDisplay: Bool { get }
    /// Called on the main thread whenever a power source changes.
    var onChange: (() -> Void)? { get set }
    /// Called on the main thread whenever the lid opens or closes.
    var onLidChange: (() -> Void)? { get set }
    /// Puts the Mac to sleep now.
    func sleepNow()
    /// Turns the displays off (the Mac keeps running).
    func turnDisplayOff()
}

@MainActor
public final class IOKitBatteryMonitor: BatteryMonitor {
    public var onChange: (() -> Void)?
    public var onLidChange: (() -> Void)?

    /// `nonisolated(unsafe)` so `deinit` (nonisolated) can release them; only
    /// written in `init`.
    private nonisolated(unsafe) var runLoopSource: CFRunLoopSource?
    private nonisolated(unsafe) var rootDomainPort: IONotificationPortRef?
    private nonisolated(unsafe) var rootDomainNotifier: io_object_t = 0
    private var lastLidClosed = false

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

        self.lastLidClosed = self.isLidClosed
        self.observeRootDomain(context: context)
    }

    deinit {
        if let runLoopSource {
            CFRunLoopSourceInvalidate(runLoopSource)
        }
        if self.rootDomainNotifier != 0 {
            IOObjectRelease(self.rootDomainNotifier)
        }
        if let rootDomainPort {
            IONotificationPortDestroy(rootDomainPort)
        }
    }

    /// The root domain posts a general-interest message when the lid opens or
    /// closes (among others). Rather than decode message types, re-read
    /// `AppleClamshellState` on every message and report actual changes.
    private func observeRootDomain(context: UnsafeMutableRawPointer) {
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        IONotificationPortSetDispatchQueue(port, .main)
        let rootDomain = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard rootDomain != 0 else {
            IONotificationPortDestroy(port)
            return
        }
        defer { IOObjectRelease(rootDomain) }

        var notifier: io_object_t = 0
        let result = IOServiceAddInterestNotification(port, rootDomain, kIOGeneralInterest, { context, _, _, _ in
            guard let address = context.map({ UInt(bitPattern: $0) }) else { return }
            MainActor.assumeIsolated {
                guard let pointer = UnsafeMutableRawPointer(bitPattern: address) else { return }
                Unmanaged<IOKitBatteryMonitor>.fromOpaque(pointer).takeUnretainedValue().rootDomainDidChange()
            }
        }, context, &notifier)

        guard result == KERN_SUCCESS else {
            IONotificationPortDestroy(port)
            return
        }
        self.rootDomainPort = port
        self.rootDomainNotifier = notifier
    }

    private func rootDomainDidChange() {
        let closed = self.isLidClosed
        guard closed != self.lastLidClosed else { return }
        self.lastLidClosed = closed
        self.onLidChange?()
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

    public var hasExternalDisplay: Bool {
        var displays = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        // Online, not active: a closed lid can take displays out of the
        // active list while they're still connected.
        guard CGGetOnlineDisplayList(UInt32(displays.count), &displays, &count) == .success else { return false }
        return displays.prefix(Int(count)).contains { CGDisplayIsBuiltin($0) == 0 }
    }

    public func sleepNow() {
        let port = IOPMFindPowerManagement(kIOMainPortDefault)
        guard port != 0 else { return }
        IOPMSleepSystem(port)
        IOServiceClose(port)
    }

    /// With `SleepDisabled` on, closing the lid no longer switches the
    /// built-in panel off (that normally happens as part of lid-close sleep),
    /// so it stays lit under the lid. `pmset displaysleepnow` needs no
    /// privileges; opening the lid turns the display back on.
    public func turnDisplayOff() {
        Task.detached {
            _ = ProcessRunner.run("/usr/bin/pmset", ["displaysleepnow"])
        }
    }
}
