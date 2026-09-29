//
//  LidSleepController+Shared.swift
//  Caffeine
//
//  App-only: not part of the CaffeineCore test package, which builds
//  controllers with fakes instead.
//

import Foundation

extension LidSleepController {
    static let shared = LidSleepController(
        settings: PmsetSleepSettingBackend(),
        authenticator: makeAuthenticator(),
        battery: IOKitBatteryMonitor()
    )

    private static func makeAuthenticator() -> any UserAuthenticator {
        #if DEBUG
        // Integration test hook (scripts/integration-test.sh): no Touch ID
        // prompt in a headless run. Compiled out of Release builds.
        if ProcessInfo.processInfo.environment["CA_TEST_AUTOACTIVATE"] == "lid-battery" {
            return ApprovingAuthenticator()
        }
        #endif
        return LocalAuthenticator()
    }
}

#if DEBUG
private final class ApprovingAuthenticator: UserAuthenticator {
    func authenticate(reason _: String) async -> Bool {
        true
    }
}
#endif
