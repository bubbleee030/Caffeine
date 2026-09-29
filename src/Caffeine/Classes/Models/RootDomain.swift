//
//  RootDomain.swift
//  Caffeine
//

import Foundation
import IOKit

/// Reads properties of the power-management root domain (`IOPMrootDomain`)
/// from the I/O Registry. No privileges needed.
///
/// Used for `SleepDisabled` (the `pmset disablesleep` setting — `pmset -g`
/// omits it entirely while it's 0, so the registry is the reliable source)
/// and `AppleClamshellState` (lid closed).
nonisolated enum RootDomain {
    static func boolProperty(_ key: String) -> Bool? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        return IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? Bool
    }
}
