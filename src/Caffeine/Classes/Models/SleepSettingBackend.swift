//
//  SleepSettingBackend.swift
//  Caffeine
//

import Foundation

public enum SleepSettingError: LocalizedError, Equatable {
    case commandFailed(status: Int32, output: String)

    /// Debug-log text only (DZErrorLog); never shown in the UI.
    public var errorDescription: String? {
        switch self {
        case let .commandFailed(status, output):
            "Command failed with status \(status): \(output.trimmingCharacters(in: .whitespacesAndNewlines))"
        }
    }
}

/// Abstraction over the system-wide `SleepDisabled` power setting
/// (`pmset disablesleep`), which keeps a Mac awake even with the lid closed on
/// battery. Production uses ``PmsetSleepSettingBackend``; tests inject a fake.
@MainActor
public protocol SleepSettingBackend: AnyObject {
    /// Current `SleepDisabled` value; `nil` if it couldn't be read.
    func isSleepDisabled() -> Bool?
    /// Switches the setting off the main thread. Throws if it failed.
    func setSleepDisabled(_ disabled: Bool) async throws
    /// Same as ``setSleepDisabled(_:)`` but blocks (up to 5 s). Only for app
    /// termination, where async work would never run.
    func setSleepDisabledImmediately(_ disabled: Bool) throws
    /// Whether the passwordless sudoers rule file exists.
    var isPasswordlessRuleInstalled: Bool { get }
    /// Installs the sudoers rule behind a single administrator prompt. Throws
    /// if the user cancels or installation fails.
    func installPasswordlessRule() async throws
}

/// Runs `sudo -n /usr/bin/pmset disablesleep 0|1`, relying on the rule from
/// ``SudoersRule``. `-n` makes sudo fail instead of prompting when the rule is
/// missing.
@MainActor
public final class PmsetSleepSettingBackend: SleepSettingBackend {
    public init() {}

    public func isSleepDisabled() -> Bool? {
        RootDomain.boolProperty("SleepDisabled")
    }

    public func setSleepDisabled(_ disabled: Bool) async throws {
        let arguments = Self.sudoArguments(disabled)
        let result = await Task.detached { ProcessRunner.run("/usr/bin/sudo", arguments) }.value
        try Self.check(result)
    }

    public func setSleepDisabledImmediately(_ disabled: Bool) throws {
        try Self.check(ProcessRunner.run("/usr/bin/sudo", Self.sudoArguments(disabled), timeout: 5))
    }

    public var isPasswordlessRuleInstalled: Bool {
        FileManager.default.fileExists(atPath: SudoersRule.path)
    }

    public func installPasswordlessRule() async throws {
        let script = try SudoersRule.installAppleScript(
            userName: NSUserName(),
            prompt: String(
                localized: "Caffeine needs your administrator password once to allow closed-lid mode on battery."
            )
        )
        // Long timeout: the user is typing a password.
        let result = await Task.detached {
            ProcessRunner.run("/usr/bin/osascript", ["-e", script], timeout: 300)
        }.value
        try Self.check(result)
    }

    private static func sudoArguments(_ disabled: Bool) -> [String] {
        ["-n", "/usr/bin/pmset", "disablesleep", disabled ? "1" : "0"]
    }

    private static func check(_ result: ProcessRunner.Result) throws {
        guard result.status == 0 else {
            throw SleepSettingError.commandFailed(status: result.status, output: result.output)
        }
    }
}
