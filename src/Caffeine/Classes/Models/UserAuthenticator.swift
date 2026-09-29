//
//  UserAuthenticator.swift
//  Caffeine
//

#if canImport(DZFoundation)
import DZFoundation
#endif
import LocalAuthentication

/// Asks the user to confirm an action. Production uses ``LocalAuthenticator``;
/// tests inject a fake.
@MainActor
public protocol UserAuthenticator: AnyObject {
    /// `reason` completes macOS's "Caffeine is trying to …" prompt.
    func authenticate(reason: String) async -> Bool
}

/// Touch ID, falling back to the login password (also works on Macs without
/// Touch ID).
@MainActor
public final class LocalAuthenticator: UserAuthenticator {
    public init() {}

    public func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            #if canImport(DZFoundation)
            DZErrorLog(error)
            #endif
            return false
        }
    }
}
