//
//  TestHook.swift
//  Caffeine
//

#if DEBUG
import Foundation

/// Hooks for `scripts/integration-test.sh`. Compiled out of Release builds.
enum TestHook {
    /// `CA_TEST_AUTOACTIVATE`: activate on launch without showing the
    /// preferences window or writing preferences.
    /// - `lid-closed`: also hold the AC lid-close assertion
    /// - `lid-battery`: also engage closed-lid mode on battery, auto-approving
    ///   the Touch ID step
    /// - anything else: plain activation
    static let autoActivateMode = ProcessInfo.processInfo.environment["CA_TEST_AUTOACTIVATE"]

    static var allowsLidClose: Bool {
        autoActivateMode == "lid-closed" || autoActivateMode == "lid-battery"
    }

    static var engagesLidSleep: Bool {
        autoActivateMode == "lid-battery"
    }
}
#endif
