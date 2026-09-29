# Closed-Lid Mode on Battery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a portable Mac keep running with the lid closed on battery while Caffeine is active, confirmed by Touch ID each time, with normal sleep always restored.

**Architecture:** Caffeine drops the App Sandbox and toggles the system-wide `SleepDisabled` setting with `sudo -n /usr/bin/pmset disablesleep 0|1`, allowed by a one-time, narrowly scoped sudoers rule. A `@MainActor @Observable LidSleepController` owns the state machine and talks to three protocol-backed boundaries (`SleepSettingBackend`, `UserAuthenticator`, `BatteryMonitor`) so all logic is unit-tested with fakes. It persists a flag before disabling sleep and restores on deactivate, quit, SIGTERM, low battery and next launch.

**Tech Stack:** Swift 6.4 toolchain (app in Swift 5 mode with default MainActor isolation; test package in Swift 6 mode), SwiftUI + AppKit, IOKit (`IOPMrootDomain`, `IOPowerSources`), LocalAuthentication, XCTest via `swift test`.

**Spec:** `docs/superpowers/specs/2026-09-29-closed-lid-battery-mode-design.md`

## Global Constraints

- Branch: `feature/closed-lid-battery`. One commit per task.
- **Never edit** `src/Caffeine.xcodeproj/**`. Files under `src/Caffeine/Classes/` and `src/Caffeine/Resources/` are picked up automatically.
- Build: `xcodebuild -project src/Caffeine.xcodeproj -scheme Caffeine -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO` — must print `** BUILD SUCCEEDED **` with **no** `warning:` lines from `src/Caffeine/Classes` (the `appintentsmetadataprocessor` warning is expected and ignored).
- Unit tests: `swift test` (root `Package.swift`). Integration: `scripts/integration-test.sh`.
- Run `swiftformat .` after every successful build, before committing.
- Logging: `DZLog`/`DZErrorLog` only, wrapped in `#if canImport(DZFoundation)` in files compiled by `Package.swift`. No `print`, `os.Logger`, `NSLog`.
- Every user-facing string localized in all 14 locales (`de en es fr it ja ko nl pt pt-BR ru uk zh-Hans zh-Hant`) and listed in `LocalizationTests.expectedKeys`.
- Model files compiled by `Package.swift` must declare isolation explicitly (`@MainActor` or `nonisolated`) — the package does not use the app's default MainActor isolation.
- Sudoers rule path: `/etc/sudoers.d/caffeine-lid`. Allowed commands exactly: `/usr/bin/pmset disablesleep 0`, `/usr/bin/pmset disablesleep 1`.
- UserDefaults keys: `CALidSleepOverrideActive` (Bool), `CALidSleepBatteryThreshold` (Int, default 20, choices 10/20/30/50).
- User-facing changes go under `## [Unreleased]` in `CHANGELOG.md`.

## File Map

| File | Responsibility |
|---|---|
| `src/Caffeine/Resources/Caffeine.entitlements` | Modify: empty (no sandbox) |
| `src/Caffeine/Resources/Info.plist` | Modify: drop `SUEnableInstallerLauncherService` |
| `src/Caffeine/Classes/Models/ProcessRunner.swift` | Create: run a CLI tool with timeout, capture output |
| `src/Caffeine/Classes/Models/RootDomain.swift` | Create: read Bool properties of `IOPMrootDomain` |
| `src/Caffeine/Classes/Models/SudoersRule.swift` | Create: pure builders for the rule text, root shell command, AppleScript |
| `src/Caffeine/Classes/Models/SleepSettingBackend.swift` | Create: protocol + `PmsetSleepSettingBackend` |
| `src/Caffeine/Classes/Models/UserAuthenticator.swift` | Create: protocol + `LocalAuthenticator` (Touch ID / password) |
| `src/Caffeine/Classes/Models/BatteryMonitor.swift` | Create: `PowerSnapshot`, protocol + `IOKitBatteryMonitor` |
| `src/Caffeine/Classes/Models/LidSleepController.swift` | Create: state machine, request queue, restore paths |
| `src/Caffeine/Classes/Models/LidSleepController+Shared.swift` | Create (app only, not in Package.swift): production `shared` + DEBUG test authenticator |
| `src/Caffeine/Classes/ViewModels/CaffeineViewModel.swift` | Modify: engage/restore wiring, setup alert, recovery |
| `src/Caffeine/Classes/AppDelegate.swift` | Modify: SIGTERM → `NSApp.terminate` |
| `src/Caffeine/Classes/Views/MenuBarController.swift` | Modify: synchronous restore on quit; "Closed-lid mode is on" item |
| `src/Caffeine/Classes/Views/PreferencesView.swift` | Modify: footnote, battery threshold picker, failure text |
| `src/Caffeine/Resources/*.lproj/Localizable.strings` | Modify: 11 new keys, 1 removed |
| `Package.swift` | Modify: add new model sources |
| `Tests/CaffeineCoreTests/SudoersRuleTests.swift` | Create |
| `Tests/CaffeineCoreTests/ProcessRunnerTests.swift` | Create |
| `Tests/CaffeineCoreTests/LidSleepControllerTests.swift` | Create (+ fakes) |
| `Tests/CaffeineCoreTests/PackageSmokeTests.swift` | Modify: production backends smoke |
| `Tests/CaffeineCoreTests/LocalizationTests.swift` | Modify: keys |
| `scripts/integration-test.sh` | Modify: lid-battery + crash-recovery cases |
| `README.md`, `README.zh-Hant.md`, `CHANGELOG.md`, `AGENTS.md` | Modify: docs |

---

### Task 1: Remove the App Sandbox

**Files:**
- Modify: `src/Caffeine/Resources/Caffeine.entitlements`
- Modify: `src/Caffeine/Resources/Info.plist`
- Modify: `CHANGELOG.md`

**Interfaces:** Consumes nothing. Produces an unsandboxed app (later tasks spawn `sudo`/`osascript`).

- [ ] **Step 1: Replace the entitlements file**

`src/Caffeine/Resources/Caffeine.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict/>
</plist>
```

- [ ] **Step 2: Remove the sandbox-only Sparkle key from Info.plist**

Delete these two lines from `src/Caffeine/Resources/Info.plist`:

```xml
    <key>SUEnableInstallerLauncherService</key>
    <true/>
```

- [ ] **Step 3: Verify**

Run:
```bash
plutil -lint src/Caffeine/Resources/Caffeine.entitlements src/Caffeine/Resources/Info.plist
plutil -extract com.apple.security.app-sandbox raw src/Caffeine/Resources/Caffeine.entitlements; echo "exit $?"
xcodebuild -project src/Caffeine.xcodeproj -scheme Caffeine -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "warning:|error:|BUILD" | grep -v appintents
swift test 2>&1 | grep -E "Executed .* tests" | tail -1
scripts/integration-test.sh 2>&1 | tail -1
```
Expected: both files `OK`; the extract fails (`exit 1`); `** BUILD SUCCEEDED **` with no warnings; `Executed 22 tests, with 0 failures`; `==> Integration checks passed`.

- [ ] **Step 4: Changelog**

Under `## [Unreleased]` in `CHANGELOG.md`, add to the existing `### Changed` section:

```markdown
- Caffeine is no longer sandboxed, so it can turn off lid-close sleep on battery (see "Allow Mac to run with lid closed"). Previous settings are not carried over.
```

- [ ] **Step 5: Format and commit**

```bash
swiftformat .
git add src/Caffeine/Resources/Caffeine.entitlements src/Caffeine/Resources/Info.plist CHANGELOG.md
git commit -m "Remove the App Sandbox

Closed-lid mode on battery needs to run pmset via sudo, which the sandbox
forbids. Drops the sandbox, Sparkle's sandbox XPC exceptions and unused
network/file entitlements; Hardened Runtime stays on."
```

---

### Task 2: Process, registry and sudoers helpers

**Files:**
- Create: `src/Caffeine/Classes/Models/ProcessRunner.swift`
- Create: `src/Caffeine/Classes/Models/RootDomain.swift`
- Create: `src/Caffeine/Classes/Models/SudoersRule.swift`
- Modify: `Package.swift`
- Test: `Tests/CaffeineCoreTests/ProcessRunnerTests.swift`, `Tests/CaffeineCoreTests/SudoersRuleTests.swift`

**Interfaces:**
- Produces:
  - `nonisolated enum ProcessRunner { struct Result: Equatable, Sendable { var status: Int32; var output: String }; static func run(_ executablePath: String, _ arguments: [String], timeout: TimeInterval = 10) -> Result }` — status `-1` = couldn't launch / timed out.
  - `nonisolated enum RootDomain { static func boolProperty(_ key: String) -> Bool? }`
  - `nonisolated enum SudoersRule { enum Error: Swift.Error, Equatable { case invalidUserName(String) }; static let path: String; static func isValidUserName(_:) -> Bool; static func lines(userName:) throws -> [String]; static func installShellCommand(userName:) throws -> String; static func installAppleScript(userName:prompt:) throws -> String; static func appleScriptLiteral(_:) -> String }`

- [ ] **Step 1: Add the new sources to Package.swift**

In `Package.swift`, replace the `sources:` array with (Tasks 3 and 4 add the remaining files):

```swift
            sources: [
                "LaunchAtLoginManager.swift",
                "LaunchItemBackend.swift",
                "PowerAssertionBackend.swift",
                "ProcessRunner.swift",
                "RootDomain.swift",
                "SleepPreventionManager.swift",
                "SudoersRule.swift",
            ]
```

- [ ] **Step 2: Write the failing tests**

`Tests/CaffeineCoreTests/ProcessRunnerTests.swift`:

```swift
//
//  ProcessRunnerTests.swift
//  CaffeineCoreTests
//

import XCTest
@testable import CaffeineCore

final class ProcessRunnerTests: XCTestCase {
    func testCapturesOutputAndStatus() {
        let result = ProcessRunner.run("/bin/sh", ["-c", "echo hello; echo oops >&2; exit 3"])

        XCTAssertEqual(result.status, 3)
        XCTAssertTrue(result.output.contains("hello"))
        XCTAssertTrue(result.output.contains("oops"))
    }

    func testMissingExecutableReturnsMinusOne() {
        let result = ProcessRunner.run("/nonexistent/tool", [])

        XCTAssertEqual(result.status, -1)
    }

    func testTimeoutTerminatesAndReturnsMinusOne() {
        let start = Date()

        let result = ProcessRunner.run("/bin/sleep", ["5"], timeout: 0.5)

        XCTAssertEqual(result.status, -1)
        XCTAssertLessThan(Date().timeIntervalSince(start), 3)
    }
}

final class RootDomainTests: XCTestCase {
    func testReadsSleepDisabled() {
        XCTAssertNotNil(RootDomain.boolProperty("SleepDisabled"))
    }

    func testUnknownKeyIsNil() {
        XCTAssertNil(RootDomain.boolProperty("CaffeineDefinitelyNotAKey"))
    }
}
```

`Tests/CaffeineCoreTests/SudoersRuleTests.swift`:

```swift
//
//  SudoersRuleTests.swift
//  CaffeineCoreTests
//

import XCTest
@testable import CaffeineCore

final class SudoersRuleTests: XCTestCase {
    func testRuleAllowsOnlyDisablesleep() throws {
        let lines = try SudoersRule.lines(userName: "bubble")

        XCTAssertEqual(lines, [
            "# Installed by Caffeine. Allows switching lid-close sleep without a password.",
            "bubble ALL=(root) NOPASSWD: /usr/bin/pmset disablesleep 0, /usr/bin/pmset disablesleep 1",
        ])
    }

    func testRejectsUnsafeUserNames() {
        for name in ["", "-rf", "a b", "root'", "a\nb", "ü", "a;b", "a\"b"] {
            XCTAssertThrowsError(try SudoersRule.lines(userName: name), "accepted \(name.debugDescription)")
        }
    }

    func testAcceptsTypicalUserNames() {
        for name in ["bubble", "john.doe", "a_b-c", "user42"] {
            XCTAssertTrue(SudoersRule.isValidUserName(name), name)
        }
    }

    func testRulePassesVisudo() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("caffeine-lid-test-\(UUID().uuidString)")
        try (SudoersRule.lines(userName: "bubble").joined(separator: "\n") + "\n")
            .write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = ProcessRunner.run("/usr/sbin/visudo", ["-cf", url.path])

        XCTAssertEqual(result.status, 0, result.output)
    }

    func testInstallCommandIsValidShell() throws {
        let command = try SudoersRule.installShellCommand(userName: "bubble")

        let result = ProcessRunner.run("/bin/sh", ["-n", "-c", command])

        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(command.contains("/usr/sbin/visudo -cf"))
        XCTAssertTrue(command.contains("-m 0440 -o root -g wheel"))
        XCTAssertTrue(command.contains("/etc/sudoers.d/caffeine-lid"))
    }

    func testAppleScriptLiteralEscapesQuotesAndBackslashes() {
        XCTAssertEqual(SudoersRule.appleScriptLiteral(#"a"b\c"#), #""a\"b\\c""#)
    }

    func testInstallAppleScriptCompiles() throws {
        let script = try SudoersRule.installAppleScript(userName: "bubble", prompt: #"Say "hi""#)
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("caffeine-lid-\(UUID().uuidString).scpt")
        defer { try? FileManager.default.removeItem(at: output) }

        let result = ProcessRunner.run("/usr/bin/osacompile", ["-o", output.path, "-e", script])

        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(script.hasSuffix(#"with administrator privileges with prompt "Say \"hi\"""#))
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `swift test 2>&1 | tail -5`
Expected: build failure — `cannot find 'ProcessRunner' in scope` (source files listed in Package.swift don't exist yet also errors; both are fine).

- [ ] **Step 4: Implement ProcessRunner**

`src/Caffeine/Classes/Models/ProcessRunner.swift`:

```swift
//
//  ProcessRunner.swift
//  Caffeine
//

import Foundation

/// Runs a command-line tool synchronously and captures its combined
/// stdout/stderr. Blocking — call it from a detached task unless blocking is
/// intended (e.g. during app termination).
///
/// Output is read after the tool exits, so it's only suitable for tools with
/// small output (well under the 64 KB pipe buffer), like `pmset` or `sudo`.
nonisolated enum ProcessRunner {
    struct Result: Equatable, Sendable {
        var status: Int32
        var output: String
    }

    /// Returns status `-1` if the tool couldn't be launched or didn't finish
    /// within `timeout` seconds (it is terminated in that case).
    static func run(_ executablePath: String, _ arguments: [String], timeout: TimeInterval = 10) -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }

        do {
            try process.run()
        } catch {
            return Result(status: -1, output: error.localizedDescription)
        }

        guard finished.wait(timeout: .now() + timeout) == .success else {
            process.terminate()
            return Result(status: -1, output: "Timed out after \(timeout) s")
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return Result(status: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
    }
}
```

- [ ] **Step 5: Implement RootDomain**

`src/Caffeine/Classes/Models/RootDomain.swift`:

```swift
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
```

- [ ] **Step 6: Implement SudoersRule**

`src/Caffeine/Classes/Models/SudoersRule.swift`:

```swift
//
//  SudoersRule.swift
//  Caffeine
//

import Foundation

/// Builds the `/etc/sudoers.d` rule that lets the current user switch
/// `pmset disablesleep` without a password, and the one-time AppleScript that
/// installs it with administrator privileges. Pure string building, no side
/// effects.
nonisolated enum SudoersRule {
    enum Error: Swift.Error, Equatable {
        case invalidUserName(String)
    }

    static let path = "/etc/sudoers.d/caffeine-lid"

    /// Must not contain a single quote: the lines are single-quoted in the
    /// root shell command.
    private static let comment = "# Installed by Caffeine. Allows switching lid-close sleep without a password."

    /// macOS short user names use only these characters. Anything else is
    /// rejected rather than escaped, because the name ends up in a root shell
    /// command and in a sudoers file.
    static func isValidUserName(_ name: String) -> Bool {
        !name.isEmpty && !name.hasPrefix("-") && name.unicodeScalars.allSatisfy {
            $0.isASCII && (CharacterSet.alphanumerics.contains($0) || "._-".unicodeScalars.contains($0))
        }
    }

    static func lines(userName: String) throws -> [String] {
        guard self.isValidUserName(userName) else { throw Error.invalidUserName(userName) }
        return [
            self.comment,
            "\(userName) ALL=(root) NOPASSWD: /usr/bin/pmset disablesleep 0, /usr/bin/pmset disablesleep 1",
        ]
    }

    /// Shell command run as root: write the rule to a temp file, validate it
    /// with `visudo`, then install it 0440 root:wheel. Nothing is installed if
    /// `visudo` rejects the file, and the temp file is always removed.
    static func installShellCommand(userName: String) throws -> String {
        let quotedLines = try self.lines(userName: userName).map { "'\($0)'" }.joined(separator: " ")
        return "tmp=$(/usr/bin/mktemp /tmp/caffeine-lid.XXXXXX) && "
            + "/usr/bin/printf '%s\\n' \(quotedLines) > \"$tmp\" && "
            + "/usr/sbin/visudo -cf \"$tmp\" && "
            + "/usr/bin/install -m 0440 -o root -g wheel \"$tmp\" \(self.path); "
            + "status=$?; /bin/rm -f \"$tmp\"; exit $status"
    }

    /// AppleScript for `osascript -e`, showing macOS's administrator prompt once.
    static func installAppleScript(userName: String, prompt: String) throws -> String {
        let command = try self.installShellCommand(userName: userName)
        return "do shell script \(self.appleScriptLiteral(command)) "
            + "with administrator privileges with prompt \(self.appleScriptLiteral(prompt))"
    }

    /// Quotes `string` as an AppleScript string literal.
    static func appleScriptLiteral(_ string: String) -> String {
        let escaped = string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
```

- [ ] **Step 7: Run tests to verify they pass**

Run: `swift test 2>&1 | grep -E "error|failed|Executed .* tests" | tail -5`
Expected: `Executed 34 tests, with 0 failures` (22 existing + 5 ProcessRunner/RootDomain + 7 SudoersRule).

- [ ] **Step 8: Build, format, commit**

```bash
xcodebuild -project src/Caffeine.xcodeproj -scheme Caffeine -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "warning:|error:|BUILD" | grep -v appintents
swiftformat .
git add Package.swift src/Caffeine/Classes/Models/ProcessRunner.swift src/Caffeine/Classes/Models/RootDomain.swift src/Caffeine/Classes/Models/SudoersRule.swift Tests/CaffeineCoreTests/ProcessRunnerTests.swift Tests/CaffeineCoreTests/SudoersRuleTests.swift
git commit -m "Add process, IOPMrootDomain and sudoers-rule helpers for closed-lid mode"
```
Expected build: `** BUILD SUCCEEDED **`, no warnings.

---

### Task 3: Production backends (pmset, Touch ID, battery)

**Files:**
- Create: `src/Caffeine/Classes/Models/SleepSettingBackend.swift`
- Create: `src/Caffeine/Classes/Models/UserAuthenticator.swift`
- Create: `src/Caffeine/Classes/Models/BatteryMonitor.swift`
- Modify: `Package.swift`
- Modify: `Tests/CaffeineCoreTests/PackageSmokeTests.swift`

**Interfaces:**
- Consumes: `ProcessRunner.run`, `RootDomain.boolProperty`, `SudoersRule.path`, `SudoersRule.installAppleScript(userName:prompt:)` (Task 2).
- Produces:
  - `public enum SleepSettingError: Error, Equatable { case commandFailed(status: Int32, output: String) }`
  - `@MainActor public protocol SleepSettingBackend: AnyObject { func isSleepDisabled() -> Bool?; func setSleepDisabled(_ disabled: Bool) async throws; func setSleepDisabledImmediately(_ disabled: Bool) throws; var isPasswordlessRuleInstalled: Bool { get }; func installPasswordlessRule() async throws }`
  - `@MainActor public final class PmsetSleepSettingBackend: SleepSettingBackend` with `public init()`
  - `@MainActor public protocol UserAuthenticator: AnyObject { func authenticate(reason: String) async -> Bool }`
  - `@MainActor public final class LocalAuthenticator: UserAuthenticator` with `public init()`
  - `public struct PowerSnapshot: Equatable, Sendable { public var isOnBattery: Bool; public var percent: Int?; public init(isOnBattery:percent:) }`
  - `@MainActor public protocol BatteryMonitor: AnyObject { var snapshot: PowerSnapshot { get }; var isLidClosed: Bool { get }; var onChange: (() -> Void)? { get set }; func sleepNow() }`
  - `@MainActor public final class IOKitBatteryMonitor: BatteryMonitor` with `public init()`

- [ ] **Step 1: Add sources to Package.swift**

Replace the `sources:` array with:

```swift
            sources: [
                "BatteryMonitor.swift",
                "LaunchAtLoginManager.swift",
                "LaunchItemBackend.swift",
                "PowerAssertionBackend.swift",
                "ProcessRunner.swift",
                "RootDomain.swift",
                "SleepPreventionManager.swift",
                "SleepSettingBackend.swift",
                "SudoersRule.swift",
                "UserAuthenticator.swift",
            ]
```

- [ ] **Step 2: Write the failing smoke tests**

Append to the `PackageSmokeTests` class in `Tests/CaffeineCoreTests/PackageSmokeTests.swift`:

```swift
    @MainActor
    func testPmsetBackendReadsSleepDisabled() {
        XCTAssertNotNil(PmsetSleepSettingBackend().isSleepDisabled())
    }

    @MainActor
    func testBatteryMonitorReadsSnapshot() {
        let monitor = IOKitBatteryMonitor()
        let snapshot = monitor.snapshot

        // Desktops have no battery: percent is nil and never "on battery".
        if snapshot.percent == nil {
            XCTAssertFalse(snapshot.isOnBattery)
        } else {
            XCTAssertTrue((0...100).contains(snapshot.percent!))
        }
        _ = monitor.isLidClosed
    }
```

- [ ] **Step 3: Run to verify failure**

Run: `swift test 2>&1 | grep -E "error:" | head -3`
Expected: `cannot find 'PmsetSleepSettingBackend' in scope` (or missing-file errors).

- [ ] **Step 4: Implement SleepSettingBackend**

`src/Caffeine/Classes/Models/SleepSettingBackend.swift`:

```swift
//
//  SleepSettingBackend.swift
//  Caffeine
//

import Foundation

public enum SleepSettingError: Error, Equatable {
    case commandFailed(status: Int32, output: String)
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
```

- [ ] **Step 5: Implement UserAuthenticator**

`src/Caffeine/Classes/Models/UserAuthenticator.swift`:

```swift
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
```

- [ ] **Step 6: Implement BatteryMonitor**

`src/Caffeine/Classes/Models/BatteryMonitor.swift`:

```swift
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
```

- [ ] **Step 7: Run tests to verify they pass**

Run: `swift test 2>&1 | grep -E "error|failed|Executed .* tests" | tail -5`
Expected: `Executed 36 tests, with 0 failures`.

- [ ] **Step 8: Build, format, commit**

```bash
xcodebuild -project src/Caffeine.xcodeproj -scheme Caffeine -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "warning:|error:|BUILD" | grep -v appintents
swiftformat .
git add Package.swift src/Caffeine/Classes/Models/SleepSettingBackend.swift src/Caffeine/Classes/Models/UserAuthenticator.swift src/Caffeine/Classes/Models/BatteryMonitor.swift Tests/CaffeineCoreTests/PackageSmokeTests.swift
git commit -m "Add pmset, Touch ID and battery backends for closed-lid mode"
```
Expected build: `** BUILD SUCCEEDED **`, no warnings.

---

### Task 4: LidSleepController

**Files:**
- Create: `src/Caffeine/Classes/Models/LidSleepController.swift`
- Modify: `Package.swift`
- Test: `Tests/CaffeineCoreTests/LidSleepControllerTests.swift`

**Interfaces:**
- Consumes: `SleepSettingBackend`, `UserAuthenticator`, `BatteryMonitor`, `PowerSnapshot` (Task 3).
- Produces (all `@MainActor`):
  - `public final class LidSleepController` (`@Observable`)
  - `public enum State { case off, enabling, on, restoring }`, `public enum Failure { case setupFailed, authenticationDenied, commandFailed, lowBattery }`
  - `public static let overrideFlagKey = "CALidSleepOverrideActive"`, `public static let batteryThresholdKey = "CALidSleepBatteryThreshold"`, `public static let defaultBatteryThreshold = 20`
  - `public private(set) var state: State`, `public private(set) var lastFailure: Failure?`, `public var batteryThreshold: Int { get }`
  - `public var confirmSetup: @MainActor () async -> Bool`
  - `public init(settings: any SleepSettingBackend, authenticator: any UserAuthenticator, battery: any BatteryMonitor, defaults: UserDefaults = .standard)`
  - `public func requestRecovery()`, `public func requestEngage()`, `public func requestRestore()`, `public func waitUntilIdle() async`, `public func restoreImmediately()`
  - internal (for tests): `func engage() async`, `func restore(sleepIfLidClosed: Bool = false) async`, `func recoverOnLaunch() async`

- [ ] **Step 1: Add the source to Package.swift**

Add `"LidSleepController.swift",` after `"LaunchItemBackend.swift",` in the `sources:` array.

- [ ] **Step 2: Write the failing tests**

`Tests/CaffeineCoreTests/LidSleepControllerTests.swift`:

```swift
//
//  LidSleepControllerTests.swift
//  CaffeineCoreTests
//

import XCTest
@testable import CaffeineCore

@MainActor
final class LidSleepControllerTests: XCTestCase {
    private var settings: FakeSleepSettings!
    private var authenticator: FakeAuthenticator!
    private var battery: FakeBattery!
    private var defaults: UserDefaults!
    private var controller: LidSleepController!

    private var flag: Bool {
        self.defaults.bool(forKey: LidSleepController.overrideFlagKey)
    }

    override func setUp() async throws {
        let suite = "LidSleepControllerTests-\(UUID().uuidString)"
        self.defaults = UserDefaults(suiteName: suite)
        self.addTeardownBlock { UserDefaults().removePersistentDomain(forName: suite) }
        self.settings = FakeSleepSettings()
        self.authenticator = FakeAuthenticator()
        self.battery = FakeBattery()
        self.controller = LidSleepController(
            settings: self.settings,
            authenticator: self.authenticator,
            battery: self.battery,
            defaults: self.defaults
        )
    }

    // MARK: - Engage

    func testEngageAuthenticatesThenDisablesSleep() async {
        await self.controller.engage()

        XCTAssertEqual(self.controller.state, .on)
        XCTAssertNil(self.controller.lastFailure)
        XCTAssertEqual(self.settings.sleepDisabled, true)
        XCTAssertEqual(self.authenticator.reasons.count, 1)
        XCTAssertTrue(self.flag)
    }

    func testEngagePersistsFlagBeforeDisablingSleep() async {
        var flagWhenDisabling: Bool?
        self.settings.onSetSleepDisabled = { [unowned self] disabled in
            if disabled { flagWhenDisabling = self.flag }
        }

        await self.controller.engage()

        XCTAssertEqual(flagWhenDisabling, true)
    }

    func testDeniedAuthenticationLeavesSleepAlone() async {
        self.authenticator.approve = false

        await self.controller.engage()

        XCTAssertEqual(self.controller.state, .off)
        XCTAssertEqual(self.controller.lastFailure, .authenticationDenied)
        XCTAssertEqual(self.settings.calls, [])
        XCTAssertFalse(self.flag)
    }

    func testMissingRuleIsConfirmedAndInstalledBeforeEnabling() async {
        self.settings.isPasswordlessRuleInstalled = false
        var confirmations = 0
        self.controller.confirmSetup = {
            confirmations += 1
            return true
        }

        await self.controller.engage()

        XCTAssertEqual(confirmations, 1)
        XCTAssertEqual(self.settings.calls, ["install", "set(true)"])
        XCTAssertEqual(self.controller.state, .on)
    }

    func testDeclinedSetupInstallsNothing() async {
        self.settings.isPasswordlessRuleInstalled = false
        self.controller.confirmSetup = { false }

        await self.controller.engage()

        XCTAssertEqual(self.settings.calls, [])
        XCTAssertEqual(self.authenticator.reasons, [])
        XCTAssertEqual(self.controller.state, .off)
        XCTAssertEqual(self.controller.lastFailure, .setupFailed)
    }

    func testFailedInstallReportsSetupFailed() async {
        self.settings.isPasswordlessRuleInstalled = false
        self.settings.installError = TestError()

        await self.controller.engage()

        XCTAssertEqual(self.settings.calls, ["install"])
        XCTAssertEqual(self.controller.state, .off)
        XCTAssertEqual(self.controller.lastFailure, .setupFailed)
    }

    func testFailedCommandRollsBackAndClearsFlag() async {
        self.settings.enableError = TestError()

        await self.controller.engage()

        XCTAssertEqual(self.settings.calls, ["set(true)", "set(false)"])
        XCTAssertEqual(self.controller.state, .off)
        XCTAssertEqual(self.controller.lastFailure, .commandFailed)
        XCTAssertFalse(self.flag)
    }

    func testEngageRefusedOnLowBattery() async {
        self.battery.snapshot = PowerSnapshot(isOnBattery: true, percent: 15)

        await self.controller.engage()

        XCTAssertEqual(self.authenticator.reasons, [])
        XCTAssertEqual(self.settings.calls, [])
        XCTAssertEqual(self.controller.lastFailure, .lowBattery)
    }

    func testLowPercentOnACDoesNotBlockEngage() async {
        self.battery.snapshot = PowerSnapshot(isOnBattery: false, percent: 5)

        await self.controller.engage()

        XCTAssertEqual(self.controller.state, .on)
    }

    func testThresholdComesFromDefaults() async {
        self.defaults.set(50, forKey: LidSleepController.batteryThresholdKey)
        self.battery.snapshot = PowerSnapshot(isOnBattery: true, percent: 45)

        await self.controller.engage()

        XCTAssertEqual(self.controller.batteryThreshold, 50)
        XCTAssertEqual(self.controller.lastFailure, .lowBattery)
    }

    // MARK: - Restore

    func testRestoreReEnablesSleepAndClearsFlag() async {
        await self.controller.engage()

        await self.controller.restore()

        XCTAssertEqual(self.settings.sleepDisabled, false)
        XCTAssertEqual(self.controller.state, .off)
        XCTAssertFalse(self.flag)
    }

    func testRestoreWithoutEngageDoesNothing() async {
        await self.controller.restore()

        XCTAssertEqual(self.settings.calls, [])
    }

    func testFailedRestoreKeepsFlagForNextLaunch() async {
        await self.controller.engage()
        self.settings.disableError = TestError()

        await self.controller.restore()

        XCTAssertTrue(self.flag)
        XCTAssertEqual(self.controller.state, .off)
    }

    func testRestoreImmediatelyUsesBlockingCall() async {
        await self.controller.engage()

        self.controller.restoreImmediately()

        XCTAssertEqual(self.settings.calls.last, "setNow(false)")
        XCTAssertEqual(self.settings.sleepDisabled, false)
        XCTAssertFalse(self.flag)
        XCTAssertEqual(self.controller.state, .off)
    }

    // MARK: - Launch recovery

    func testRecoveryRestoresOverrideLeftByCrash() async {
        self.defaults.set(true, forKey: LidSleepController.overrideFlagKey)
        self.settings.sleepDisabled = true

        await self.controller.recoverOnLaunch()

        XCTAssertEqual(self.settings.calls, ["read", "set(false)"])
        XCTAssertFalse(self.flag)
    }

    func testRecoveryClearsStaleFlag() async {
        self.defaults.set(true, forKey: LidSleepController.overrideFlagKey)
        self.settings.sleepDisabled = false

        await self.controller.recoverOnLaunch()

        XCTAssertEqual(self.settings.calls, ["read"])
        XCTAssertFalse(self.flag)
    }

    func testRecoveryIgnoresOverrideCaffeineDidNotSet() async {
        self.settings.sleepDisabled = true

        await self.controller.recoverOnLaunch()

        XCTAssertEqual(self.settings.calls, [])
        XCTAssertEqual(self.settings.sleepDisabled, true)
    }

    // MARK: - Battery guard

    func testLowBatteryWhileOnRestoresAndSleepsIfLidClosed() async {
        await self.controller.engage()
        self.battery.snapshot = PowerSnapshot(isOnBattery: true, percent: 20)
        self.battery.isLidClosed = true

        self.battery.onChange?()
        await self.controller.waitUntilIdle()

        XCTAssertEqual(self.settings.sleepDisabled, false)
        XCTAssertEqual(self.controller.state, .off)
        XCTAssertEqual(self.controller.lastFailure, .lowBattery)
        XCTAssertEqual(self.battery.sleepNowCalls, 1)
    }

    func testLowBatteryWithLidOpenDoesNotForceSleep() async {
        await self.controller.engage()
        self.battery.snapshot = PowerSnapshot(isOnBattery: true, percent: 10)

        self.battery.onChange?()
        await self.controller.waitUntilIdle()

        XCTAssertEqual(self.settings.sleepDisabled, false)
        XCTAssertEqual(self.battery.sleepNowCalls, 0)
    }

    func testBatteryAboveThresholdKeepsClosedLidMode() async {
        await self.controller.engage()
        self.battery.snapshot = PowerSnapshot(isOnBattery: true, percent: 21)

        self.battery.onChange?()
        await self.controller.waitUntilIdle()

        XCTAssertEqual(self.controller.state, .on)
        XCTAssertEqual(self.settings.sleepDisabled, true)
    }

    // MARK: - Request queue

    func testRequestsRunInOrder() async {
        self.controller.requestEngage()
        self.controller.requestRestore()

        await self.controller.waitUntilIdle()

        XCTAssertEqual(self.settings.calls, ["set(true)", "set(false)"])
        XCTAssertEqual(self.controller.state, .off)
    }
}

// MARK: - Fakes

private struct TestError: Error {}

@MainActor
private final class FakeSleepSettings: SleepSettingBackend {
    var sleepDisabled: Bool? = false
    var isPasswordlessRuleInstalled = true
    var installError: (any Error)?
    var enableError: (any Error)?
    var disableError: (any Error)?
    var onSetSleepDisabled: ((Bool) -> Void)?
    private(set) var calls: [String] = []

    func isSleepDisabled() -> Bool? {
        self.calls.append("read")
        return self.sleepDisabled
    }

    func setSleepDisabled(_ disabled: Bool) async throws {
        try self.apply(disabled, label: "set")
    }

    func setSleepDisabledImmediately(_ disabled: Bool) throws {
        try self.apply(disabled, label: "setNow")
    }

    func installPasswordlessRule() async throws {
        self.calls.append("install")
        if let installError {
            throw installError
        }
        self.isPasswordlessRuleInstalled = true
    }

    private func apply(_ disabled: Bool, label: String) throws {
        self.calls.append("\(label)(\(disabled))")
        self.onSetSleepDisabled?(disabled)
        if let error = disabled ? self.enableError : self.disableError {
            throw error
        }
        self.sleepDisabled = disabled
    }
}

@MainActor
private final class FakeAuthenticator: UserAuthenticator {
    var approve = true
    private(set) var reasons: [String] = []

    func authenticate(reason: String) async -> Bool {
        self.reasons.append(reason)
        return self.approve
    }
}

@MainActor
private final class FakeBattery: BatteryMonitor {
    var snapshot = PowerSnapshot(isOnBattery: false, percent: 100)
    var isLidClosed = false
    var onChange: (() -> Void)?
    private(set) var sleepNowCalls = 0

    func sleepNow() {
        self.sleepNowCalls += 1
    }
}
```

- [ ] **Step 3: Run to verify failure**

Run: `swift test 2>&1 | grep -E "error:" | head -3`
Expected: `cannot find 'LidSleepController' in scope` (or a missing-file error for `LidSleepController.swift`).

- [ ] **Step 4: Implement LidSleepController**

`src/Caffeine/Classes/Models/LidSleepController.swift`:

```swift
//
//  LidSleepController.swift
//  Caffeine
//

#if canImport(DZFoundation)
import DZFoundation
#endif
import Foundation
import Observation

/// Keeps a portable Mac running with the lid closed — on battery too — by
/// switching the system-wide `SleepDisabled` power setting
/// (`pmset disablesleep`) while a Caffeine session is active.
///
/// `SleepDisabled` survives quits, crashes and reboots, so the controller
/// persists ``overrideFlagKey`` *before* switching it on and restores it on
/// every exit path: deactivation, quit (``restoreImmediately()``), low
/// battery, and the next launch (``requestRecovery()``). A `SleepDisabled`
/// that Caffeine didn't set is never touched.
///
/// Requests are serialized: each `request…` call runs after the previous one
/// finished, so a restore can't overtake an engage still waiting for Touch ID.
@MainActor
@Observable
public final class LidSleepController {
    public enum State: Equatable, Sendable {
        case off
        case enabling
        case on
        case restoring
    }

    public enum Failure: Equatable, Sendable {
        /// The one-time administrator setup was declined or failed.
        case setupFailed
        /// Touch ID / password confirmation was cancelled or failed.
        case authenticationDenied
        /// `pmset disablesleep 1` failed.
        case commandFailed
        /// On battery at or below ``batteryThreshold``.
        case lowBattery
    }

    public static let overrideFlagKey = "CALidSleepOverrideActive"
    public static let batteryThresholdKey = "CALidSleepBatteryThreshold"
    public static let defaultBatteryThreshold = 20

    public private(set) var state: State = .off
    public private(set) var lastFailure: Failure?

    /// Asked before the one-time administrator prompt; return `false` to
    /// cancel. The app replaces this with an explanatory alert.
    @ObservationIgnored
    public var confirmSetup: @MainActor () async -> Bool = { true }

    private let settings: any SleepSettingBackend
    private let authenticator: any UserAuthenticator
    private let battery: any BatteryMonitor
    private let defaults: UserDefaults
    @ObservationIgnored
    private var pending: Task<Void, Never>?

    public init(
        settings: any SleepSettingBackend,
        authenticator: any UserAuthenticator,
        battery: any BatteryMonitor,
        defaults: UserDefaults = .standard
    ) {
        self.settings = settings
        self.authenticator = authenticator
        self.battery = battery
        self.defaults = defaults
        self.battery.onChange = { [weak self] in self?.batteryDidChange() }
    }

    /// Battery percentage at or below which closed-lid mode is turned off
    /// while running on battery.
    public var batteryThreshold: Int {
        let stored = self.defaults.integer(forKey: Self.batteryThresholdKey)
        return stored > 0 ? stored : Self.defaultBatteryThreshold
    }

    // MARK: - Requests (serialized)

    /// Restores sleep if a previous run crashed while closed-lid mode was on.
    public func requestRecovery() {
        self.enqueue { await $0.recoverOnLaunch() }
    }

    public func requestEngage() {
        self.enqueue { await $0.engage() }
    }

    public func requestRestore() {
        self.enqueue { await $0.restore() }
    }

    /// Waits until every queued request has finished.
    public func waitUntilIdle() async {
        while let task = self.pending {
            await task.value
            if self.pending == task {
                self.pending = nil
            }
        }
    }

    /// Restores sleep synchronously. Call from `applicationWillTerminate`,
    /// where queued async work would never run.
    public func restoreImmediately() {
        guard self.defaults.bool(forKey: Self.overrideFlagKey) else { return }
        do {
            try self.settings.setSleepDisabledImmediately(false)
            // While enabling, a `disablesleep 1` may still be in flight and
            // land after this call; keep the flag so the next launch checks.
            if self.state != .enabling {
                self.defaults.removeObject(forKey: Self.overrideFlagKey)
            }
        } catch {
            self.log(error)
        }
        self.state = .off
    }

    // MARK: - Operations

    func engage() async {
        guard self.state == .off else { return }
        self.lastFailure = nil
        guard !self.isBatteryLow else {
            self.lastFailure = .lowBattery
            return
        }
        self.state = .enabling

        if !self.settings.isPasswordlessRuleInstalled {
            guard await self.confirmSetup() else {
                self.fail(.setupFailed)
                return
            }
            do {
                try await self.settings.installPasswordlessRule()
            } catch {
                self.log(error)
                self.fail(.setupFailed)
                return
            }
        }

        guard await self.authenticator.authenticate(reason: String(localized: "enable closed-lid mode")) else {
            self.fail(.authenticationDenied)
            return
        }

        // Persist first: a crash during the call must not leave an
        // unrecorded system-wide override.
        self.defaults.set(true, forKey: Self.overrideFlagKey)
        do {
            try await self.settings.setSleepDisabled(true)
            self.state = .on
        } catch {
            self.log(error)
            await self.restoreSetting()
            self.fail(.commandFailed)
        }
    }

    func restore(sleepIfLidClosed: Bool = false) async {
        guard self.defaults.bool(forKey: Self.overrideFlagKey) || self.state != .off else { return }
        self.state = .restoring
        await self.restoreSetting()
        self.state = .off
        if sleepIfLidClosed, self.battery.isLidClosed {
            self.battery.sleepNow()
        }
    }

    func recoverOnLaunch() async {
        guard self.defaults.bool(forKey: Self.overrideFlagKey) else { return }
        if self.settings.isSleepDisabled() == false {
            self.defaults.removeObject(forKey: Self.overrideFlagKey)
            return
        }
        await self.restoreSetting()
    }

    // MARK: - Private

    private var isBatteryLow: Bool {
        let snapshot = self.battery.snapshot
        guard snapshot.isOnBattery, let percent = snapshot.percent else { return false }
        return percent <= self.batteryThreshold
    }

    private func batteryDidChange() {
        guard self.state == .on, self.isBatteryLow else { return }
        self.lastFailure = .lowBattery
        self.enqueue { await $0.restore(sleepIfLidClosed: true) }
    }

    /// Re-enables sleep. The flag is only cleared on success, so a failed
    /// restore is retried by the next launch's recovery.
    private func restoreSetting() async {
        do {
            try await self.settings.setSleepDisabled(false)
            self.defaults.removeObject(forKey: Self.overrideFlagKey)
        } catch {
            self.log(error)
        }
    }

    private func fail(_ failure: Failure) {
        self.lastFailure = failure
        self.state = .off
    }

    private func enqueue(_ operation: @escaping @MainActor (LidSleepController) async -> Void) {
        let previous = self.pending
        self.pending = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            await operation(self)
        }
    }

    private func log(_ error: any Error) {
        #if canImport(DZFoundation)
        DZErrorLog(error)
        #endif
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test 2>&1 | grep -E "error|failed|Executed .* tests" | tail -5`
Expected: `Executed 57 tests, with 0 failures` (36 + 21).

- [ ] **Step 6: Build, format, commit**

```bash
xcodebuild -project src/Caffeine.xcodeproj -scheme Caffeine -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "warning:|error:|BUILD" | grep -v appintents
swiftformat .
git add Package.swift src/Caffeine/Classes/Models/LidSleepController.swift Tests/CaffeineCoreTests/LidSleepControllerTests.swift
git commit -m "Add LidSleepController for closed-lid mode on battery

Serialized engage/restore/recovery requests, flag persisted before
disabling sleep, battery guard, synchronous restore for termination."
```
Expected build: `** BUILD SUCCEEDED **`, no warnings.

---

### Task 5: Localized strings

**Files:**
- Modify: `src/Caffeine/Resources/*.lproj/Localizable.strings` (14 files)
- Modify: `Tests/CaffeineCoreTests/LocalizationTests.swift`

**Interfaces:** Produces these exact keys (used verbatim in Tasks 3, 4 and 6):

| # | Key |
|---|---|
| K1 | `Works on battery too. Requires Touch ID or your password each time Caffeine activates.` |
| K2 | `Restore sleep on battery below:` |
| K3 | `Closed-lid mode is on` |
| K4 | `Closed-lid mode on battery wasn't enabled.` |
| K5 | `Closed-lid mode was turned off because the battery is low.` |
| K6 | `Allow closed-lid mode on battery?` |
| K7 | `Caffeine will ask for your administrator password once to install a rule that only lets it turn lid-close sleep on and off. You can remove the rule at any time in Terminal with:\nsudo rm /etc/sudoers.d/caffeine-lid` (`\n` = newline) |
| K8 | `Continue` |
| K9 | `Cancel` |
| K10 | `enable closed-lid mode` |
| K11 | `Caffeine needs your administrator password once to allow closed-lid mode on battery.` |

Removed key: `Works on AC power. On battery, macOS may still sleep when the lid is closed.`

- [ ] **Step 1: Update LocalizationTests (failing test)**

In `Tests/CaffeineCoreTests/LocalizationTests.swift`, in `expectedKeys`, replace the line
`"Works on AC power. On battery, macOS may still sleep when the lid is closed.",` with:

```swift
        "Works on battery too. Requires Touch ID or your password each time Caffeine activates.",
        "Restore sleep on battery below:",
        "Closed-lid mode is on",
        "Closed-lid mode on battery wasn't enabled.",
        "Closed-lid mode was turned off because the battery is low.",
        "Allow closed-lid mode on battery?",
        "Caffeine will ask for your administrator password once to install a rule that only lets it turn lid-close sleep on and off. You can remove the rule at any time in Terminal with:\nsudo rm /etc/sudoers.d/caffeine-lid",
        "Continue",
        "Cancel",
        "enable closed-lid mode",
        "Caffeine needs your administrator password once to allow closed-lid mode on battery.",
```

Also add this test method to `LocalizationTests`:

```swift
    func testRemovedKeysAreGone() {
        for locale in self.expectedLocales {
            let url = self.resourcesURL
                .appendingPathComponent("\(locale).lproj")
                .appendingPathComponent("Localizable.strings")
            let dict = NSDictionary(contentsOf: url) as? [String: String] ?? [:]
            XCTAssertNil(
                dict["Works on AC power. On battery, macOS may still sleep when the lid is closed."],
                "\(locale) still has the AC-only footnote"
            )
        }
    }
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter LocalizationTests 2>&1 | grep -E "is missing|still has|Executed" | head -5`
Expected: failures "`<locale>` is missing 11 key(s)" and "still has the AC-only footnote".

- [ ] **Step 3: Write the strings with a script**

Save as `$SCRATCH/add_lid_strings.py` (any temp dir, not in the repo) and run `python3 $SCRATCH/add_lid_strings.py` from the repo root:

```python
import pathlib, re

RES = pathlib.Path("src/Caffeine/Resources")
OLD = "Works on AC power. On battery, macOS may still sleep when the lid is closed."
KEYS = [
    "Works on battery too. Requires Touch ID or your password each time Caffeine activates.",
    "Restore sleep on battery below:",
    "Closed-lid mode is on",
    "Closed-lid mode on battery wasn't enabled.",
    "Closed-lid mode was turned off because the battery is low.",
    "Allow closed-lid mode on battery?",
    "Caffeine will ask for your administrator password once to install a rule that only lets it turn lid-close sleep on and off. You can remove the rule at any time in Terminal with:\\nsudo rm /etc/sudoers.d/caffeine-lid",
    "Continue",
    "Cancel",
    "enable closed-lid mode",
    "Caffeine needs your administrator password once to allow closed-lid mode on battery.",
]
T = {
    "en": KEYS,
    "de": [
        "Funktioniert auch im Akkubetrieb. Erfordert jedes Mal Touch ID oder dein Passwort, wenn Caffeine aktiviert wird.",
        "Ruhezustand im Akkubetrieb wiederherstellen unter:",
        "Modus mit geschlossenem Deckel ist aktiv",
        "Der Modus mit geschlossenem Deckel für den Akkubetrieb wurde nicht aktiviert.",
        "Der Modus mit geschlossenem Deckel wurde wegen niedrigen Akkustands ausgeschaltet.",
        "Modus mit geschlossenem Deckel im Akkubetrieb erlauben?",
        "Caffeine fragt einmalig nach deinem Administratorpasswort, um eine Regel zu installieren, die nur das Ein- und Ausschalten des Ruhezustands bei geschlossenem Deckel erlaubt. Du kannst die Regel jederzeit im Terminal entfernen mit:\\nsudo rm /etc/sudoers.d/caffeine-lid",
        "Fortfahren",
        "Abbrechen",
        "den Modus mit geschlossenem Deckel zu aktivieren",
        "Caffeine benötigt einmalig dein Administratorpasswort, um den Modus mit geschlossenem Deckel im Akkubetrieb zu erlauben.",
    ],
    "es": [
        "También funciona con batería. Requiere Touch ID o tu contraseña cada vez que se activa Caffeine.",
        "Restaurar el reposo con batería por debajo de:",
        "El modo con tapa cerrada está activado",
        "No se ha activado el modo con tapa cerrada con batería.",
        "El modo con tapa cerrada se ha desactivado porque queda poca batería.",
        "¿Permitir el modo con tapa cerrada con batería?",
        "Caffeine te pedirá una sola vez tu contraseña de administrador para instalar una regla que solo le permite activar y desactivar el reposo al cerrar la tapa. Puedes eliminar la regla en cualquier momento desde Terminal con:\\nsudo rm /etc/sudoers.d/caffeine-lid",
        "Continuar",
        "Cancelar",
        "activar el modo con tapa cerrada",
        "Caffeine necesita tu contraseña de administrador una sola vez para permitir el modo con tapa cerrada con batería.",
    ],
    "fr": [
        "Fonctionne aussi sur batterie. Touch ID ou votre mot de passe est requis à chaque activation de Caffeine.",
        "Rétablir la veille sur batterie en dessous de :",
        "Le mode capot fermé est activé",
        "Le mode capot fermé sur batterie n’a pas été activé.",
        "Le mode capot fermé a été désactivé car la batterie est faible.",
        "Autoriser le mode capot fermé sur batterie ?",
        "Caffeine vous demandera une seule fois votre mot de passe administrateur pour installer une règle qui lui permet uniquement d’activer et de désactiver la veille à la fermeture du capot. Vous pouvez supprimer cette règle à tout moment dans Terminal avec :\\nsudo rm /etc/sudoers.d/caffeine-lid",
        "Continuer",
        "Annuler",
        "activer le mode capot fermé",
        "Caffeine a besoin de votre mot de passe administrateur une seule fois pour autoriser le mode capot fermé sur batterie.",
    ],
    "it": [
        "Funziona anche a batteria. Richiede Touch ID o la tua password ogni volta che Caffeine si attiva.",
        "Ripristina lo stop a batteria sotto il:",
        "La modalità coperchio chiuso è attiva",
        "La modalità coperchio chiuso a batteria non è stata attivata.",
        "La modalità coperchio chiuso è stata disattivata perché la batteria è scarica.",
        "Consentire la modalità coperchio chiuso a batteria?",
        "Caffeine ti chiederà una sola volta la password di amministratore per installare una regola che gli consente soltanto di attivare e disattivare lo stop alla chiusura del coperchio. Puoi rimuovere la regola in qualsiasi momento dal Terminale con:\\nsudo rm /etc/sudoers.d/caffeine-lid",
        "Continua",
        "Annulla",
        "attivare la modalità coperchio chiuso",
        "Caffeine ha bisogno della password di amministratore una sola volta per consentire la modalità coperchio chiuso a batteria.",
    ],
    "ja": [
        "バッテリー駆動時にも使えます。Caffeine を有効にするたびに Touch ID またはパスワードが必要です。",
        "バッテリー残量がこれ以下でスリープを復元:",
        "蓋を閉じた状態での実行がオンです",
        "バッテリー駆動時の蓋を閉じた状態での実行を有効にできませんでした。",
        "バッテリー残量が少ないため、蓋を閉じた状態での実行をオフにしました。",
        "バッテリー駆動時に蓋を閉じた状態での実行を許可しますか?",
        "Caffeine は一度だけ管理者パスワードを求め、蓋を閉じたときのスリープのオン/オフ切り替えのみを許可するルールをインストールします。このルールは「ターミナル」で次のコマンドを実行すればいつでも削除できます:\\nsudo rm /etc/sudoers.d/caffeine-lid",
        "続ける",
        "キャンセル",
        "蓋を閉じた状態での実行を有効に",
        "バッテリー駆動時に蓋を閉じた状態での実行を許可するため、Caffeine は一度だけ管理者パスワードを必要とします。",
    ],
    "ko": [
        "배터리 사용 시에도 작동합니다. Caffeine을 활성화할 때마다 Touch ID 또는 암호가 필요합니다.",
        "배터리가 다음 이하이면 잠자기 복원:",
        "덮개 닫힘 모드가 켜져 있습니다",
        "배터리 사용 시 덮개 닫힘 모드가 활성화되지 않았습니다.",
        "배터리가 부족하여 덮개 닫힘 모드가 꺼졌습니다.",
        "배터리 사용 시 덮개 닫힘 모드를 허용하겠습니까?",
        "Caffeine은 덮개를 닫을 때의 잠자기를 켜고 끄는 것만 허용하는 규칙을 설치하기 위해 관리자 암호를 한 번만 요청합니다. 터미널에서 다음 명령으로 언제든지 규칙을 제거할 수 있습니다:\\nsudo rm /etc/sudoers.d/caffeine-lid",
        "계속",
        "취소",
        "덮개 닫힘 모드를 활성화",
        "배터리 사용 시 덮개 닫힘 모드를 허용하려면 Caffeine에 관리자 암호가 한 번 필요합니다.",
    ],
    "nl": [
        "Werkt ook op batterij. Vereist elke keer dat Caffeine wordt geactiveerd Touch ID of je wachtwoord.",
        "Sluimerstand herstellen op batterij onder:",
        "Modus met gesloten deksel is aan",
        "Modus met gesloten deksel op batterij is niet ingeschakeld.",
        "Modus met gesloten deksel is uitgeschakeld omdat de batterij bijna leeg is.",
        "Modus met gesloten deksel op batterij toestaan?",
        "Caffeine vraagt één keer om je beheerderswachtwoord om een regel te installeren waarmee het alleen de sluimerstand bij gesloten deksel kan in- en uitschakelen. Je kunt de regel altijd verwijderen in Terminal met:\\nsudo rm /etc/sudoers.d/caffeine-lid",
        "Ga door",
        "Annuleer",
        "de modus met gesloten deksel in te schakelen",
        "Caffeine heeft één keer je beheerderswachtwoord nodig om de modus met gesloten deksel op batterij toe te staan.",
    ],
    "pt": [
        "Também funciona com bateria. Requer Touch ID ou a sua palavra-passe sempre que o Caffeine é ativado.",
        "Repor o repouso com bateria abaixo de:",
        "O modo de tampa fechada está ativado",
        "O modo de tampa fechada com bateria não foi ativado.",
        "O modo de tampa fechada foi desativado porque a bateria está fraca.",
        "Permitir o modo de tampa fechada com bateria?",
        "O Caffeine irá pedir a sua palavra-passe de administrador uma única vez para instalar uma regra que apenas lhe permite ativar e desativar o repouso ao fechar a tampa. Pode remover a regra a qualquer momento no Terminal com:\\nsudo rm /etc/sudoers.d/caffeine-lid",
        "Continuar",
        "Cancelar",
        "ativar o modo de tampa fechada",
        "O Caffeine precisa da sua palavra-passe de administrador uma única vez para permitir o modo de tampa fechada com bateria.",
    ],
    "pt-BR": [
        "Também funciona na bateria. Exige Touch ID ou sua senha sempre que o Caffeine é ativado.",
        "Restaurar o repouso na bateria abaixo de:",
        "O modo de tampa fechada está ativado",
        "O modo de tampa fechada na bateria não foi ativado.",
        "O modo de tampa fechada foi desativado porque a bateria está fraca.",
        "Permitir o modo de tampa fechada na bateria?",
        "O Caffeine pedirá sua senha de administrador uma única vez para instalar uma regra que só permite ativar e desativar o repouso ao fechar a tampa. Você pode remover a regra a qualquer momento no Terminal com:\\nsudo rm /etc/sudoers.d/caffeine-lid",
        "Continuar",
        "Cancelar",
        "ativar o modo de tampa fechada",
        "O Caffeine precisa da sua senha de administrador uma única vez para permitir o modo de tampa fechada na bateria.",
    ],
    "ru": [
        "Работает и от аккумулятора. При каждом включении Caffeine требуется Touch ID или пароль.",
        "Восстанавливать сон от аккумулятора ниже:",
        "Режим закрытой крышки включён",
        "Режим закрытой крышки от аккумулятора не был включён.",
        "Режим закрытой крышки выключен из-за низкого заряда аккумулятора.",
        "Разрешить режим закрытой крышки от аккумулятора?",
        "Caffeine один раз запросит пароль администратора, чтобы установить правило, которое разрешает ему только включать и выключать сон при закрытии крышки. Удалить правило можно в любой момент в Терминале командой:\\nsudo rm /etc/sudoers.d/caffeine-lid",
        "Продолжить",
        "Отменить",
        "включить режим закрытой крышки",
        "Caffeine нужен пароль администратора один раз, чтобы разрешить режим закрытой крышки от аккумулятора.",
    ],
    "uk": [
        "Працює й від акумулятора. Щоразу під час увімкнення Caffeine потрібен Touch ID або пароль.",
        "Відновлювати сон від акумулятора нижче:",
        "Режим закритої кришки ввімкнено",
        "Режим закритої кришки від акумулятора не було ввімкнено.",
        "Режим закритої кришки вимкнено через низький заряд акумулятора.",
        "Дозволити режим закритої кришки від акумулятора?",
        "Caffeine один раз попросить пароль адміністратора, щоб установити правило, яке дозволяє йому лише вмикати й вимикати сон під час закриття кришки. Видалити правило можна будь-коли в Терміналі командою:\\nsudo rm /etc/sudoers.d/caffeine-lid",
        "Продовжити",
        "Скасувати",
        "увімкнути режим закритої кришки",
        "Caffeine потрібен пароль адміністратора один раз, щоб дозволити режим закритої кришки від акумулятора.",
    ],
    "zh-Hans": [
        "使用电池时也有效。每次激活 Caffeine 都需要触控 ID 或密码。",
        "电池电量低于此值时恢复睡眠：",
        "合盖模式已开启",
        "未能开启电池供电时的合盖模式。",
        "电池电量不足，合盖模式已关闭。",
        "允许在使用电池时开启合盖模式吗？",
        "Caffeine 会请求一次管理员密码，以安装一条仅允许其开启和关闭合盖睡眠的规则。你可以随时在“终端”中使用以下命令移除该规则：\\nsudo rm /etc/sudoers.d/caffeine-lid",
        "继续",
        "取消",
        "启用合盖模式",
        "Caffeine 需要管理员密码一次，以允许在使用电池时开启合盖模式。",
    ],
    "zh-Hant": [
        "使用電池時也有效。每次啟用 Caffeine 都需要 Touch ID 或密碼。",
        "電池電量低於此值時恢復睡眠：",
        "闔蓋模式已開啟",
        "未能開啟電池供電時的闔蓋模式。",
        "電池電量不足，已關閉闔蓋模式。",
        "要允許在使用電池時開啟闔蓋模式嗎？",
        "Caffeine 會要求輸入一次管理者密碼，以安裝一條只允許它開啟和關閉闔蓋睡眠的規則。你可以隨時在「終端機」中用以下指令移除這條規則：\\nsudo rm /etc/sudoers.d/caffeine-lid",
        "繼續",
        "取消",
        "啟用闔蓋模式",
        "Caffeine 需要一次管理者密碼，才能允許在使用電池時開啟闔蓋模式。",
    ],
}

for locale, values in T.items():
    assert len(values) == len(KEYS), locale
    path = RES / f"{locale}.lproj" / "Localizable.strings"
    text = path.read_text(encoding="utf-8")
    text = re.sub(r'^"' + re.escape(OLD) + r'" = ".*";\n', "", text, flags=re.M)
    assert OLD not in text, locale
    block = "\n/* Closed-lid mode on battery */\n" + "".join(
        f'"{k}" = "{v}";\n' for k, v in zip(KEYS, values)
    )
    path.write_text(text.rstrip("\n") + "\n" + block, encoding="utf-8")
    print("updated", locale)
```

Expected output: 14 lines `updated <locale>`.

- [ ] **Step 4: Verify**

Run:
```bash
for f in src/Caffeine/Resources/*.lproj/Localizable.strings; do plutil -lint "$f" | grep -v ": OK$"; done
swift test --filter LocalizationTests 2>&1 | grep -E "Executed" | tail -1
```
Expected: no lint output; `Executed 3 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add src/Caffeine/Resources/*.lproj/Localizable.strings Tests/CaffeineCoreTests/LocalizationTests.swift
git commit -m "Localize closed-lid-on-battery strings in all 14 languages"
```

---

### Task 6: Wire into the app (view model, termination, preferences, menu)

**Files:**
- Create: `src/Caffeine/Classes/Models/LidSleepController+Shared.swift` (NOT added to Package.swift)
- Modify: `src/Caffeine/Classes/ViewModels/CaffeineViewModel.swift`
- Modify: `src/Caffeine/Classes/AppDelegate.swift`
- Modify: `src/Caffeine/Classes/Views/MenuBarController.swift`
- Modify: `src/Caffeine/Classes/Views/PreferencesView.swift`
- Modify: `CHANGELOG.md`

**Interfaces:**
- Consumes: everything from Tasks 3–5; keys K1–K9 from Task 5.
- Produces: `LidSleepController.shared` (app only); env hook `CA_TEST_AUTOACTIVATE=lid-battery` (DEBUG only) that activates with lid mode and auto-approves authentication; SIGTERM → graceful termination.

- [ ] **Step 1: Create the app-only shared instance**

`src/Caffeine/Classes/Models/LidSleepController+Shared.swift`:

```swift
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
```

- [ ] **Step 2: Wire the view model**

In `src/Caffeine/Classes/ViewModels/CaffeineViewModel.swift`:

(a) Imports — replace `import ApplicationServices` with:

```swift
import AppKit
import ApplicationServices
```

(b) Add below `private var cancellables = Set<AnyCancellable>()`:

```swift
    private let lidSleep = LidSleepController.shared
```

(c) In `init()`, replace

```swift
        self.setupObservers()

        #if DEBUG
```

with

```swift
        self.setupObservers()

        self.lidSleep.confirmSetup = { Self.confirmLidSleepSetup() }
        // Restore sleep if a previous run crashed with closed-lid mode on.
        // Queued before any activation below, so it always runs first.
        self.lidSleep.requestRecovery()

        #if DEBUG
```

(d) In the DEBUG test hook, replace

```swift
            self.activate(allowLidCloseOverride: mode == "lid-closed")
```

with

```swift
            self.activate(allowLidCloseOverride: mode == "lid-closed" || mode == "lid-battery")
```

(e) In `activate(...)`, replace

```swift
        SleepPreventionManager.shared.preventSleep(allowLidClose: allowLidClose)
```

with

```swift
        SleepPreventionManager.shared.preventSleep(allowLidClose: allowLidClose)
        if allowLidClose, self.shouldEngageLidSleep {
            self.lidSleep.requestEngage()
        }
```

(f) Replace the body of `setAllowLidClose(_:)` with:

```swift
    func setAllowLidClose(_ enabled: Bool) {
        SleepPreventionManager.shared.updateAllowLidClose(enabled)
        if !enabled {
            self.lidSleep.requestRestore()
        } else if self.isActive, self.shouldEngageLidSleep {
            self.lidSleep.requestEngage()
        }
    }
```

(g) In `deactivate()`, after `SleepPreventionManager.shared.allowSleep()` add:

```swift
        self.lidSleep.requestRestore()
```

(h) Add to the `// MARK: - Private Methods` section:

```swift
    /// Integration runs other than `lid-battery` must never trigger the
    /// administrator or Touch ID prompts.
    private var shouldEngageLidSleep: Bool {
        #if DEBUG
        if let mode = ProcessInfo.processInfo.environment["CA_TEST_AUTOACTIVATE"] {
            return mode == "lid-battery"
        }
        #endif
        return true
    }

    /// Explains the one-time administrator prompt before it appears.
    private static func confirmLidSleepSetup() -> Bool {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = String(localized: "Allow closed-lid mode on battery?")
        alert.informativeText = String(
            localized: "Caffeine will ask for your administrator password once to install a rule that only lets it turn lid-close sleep on and off. You can remove the rule at any time in Terminal with:\nsudo rm /etc/sudoers.d/caffeine-lid"
        )
        alert.addButton(withTitle: String(localized: "Continue"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        return alert.runModal() == .alertFirstButtonReturn
    }
```

(i) In `enum PreferenceKeys`, add:

```swift
    static let lidSleepBatteryThreshold = LidSleepController.batteryThresholdKey
```

- [ ] **Step 3: Restore synchronously on quit and on SIGTERM**

In `src/Caffeine/Classes/Views/MenuBarController.swift`, replace `cleanup()` with:

```swift
    func cleanup() {
        self.viewModel.deactivate()
        // deactivate() only queues an async restore, which never runs during
        // termination — restore closed-lid mode synchronously here.
        LidSleepController.shared.restoreImmediately()
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
    }
```

In `src/Caffeine/Classes/AppDelegate.swift`:

(a) Add a property below `private var menuBarController: MenuBarController?`:

```swift
    private var terminationSignalSource: DispatchSourceSignal?
```

(b) At the end of `applicationDidFinishLaunching(_:)` add:

```swift
        self.handleTerminationSignal()
```

(c) Add below `applicationWillTerminate(_:)`:

```swift
    /// `kill`/`killall` send SIGTERM, which ends the process without calling
    /// `applicationWillTerminate` — skipping cleanup such as restoring
    /// lid-close sleep. Route it through a normal termination instead.
    private func handleTerminationSignal() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler {
            MainActor.assumeIsolated {
                NSApp.terminate(nil)
            }
        }
        source.resume()
        self.terminationSignalSource = source
    }
```

- [ ] **Step 4: Menu item while closed-lid mode is on**

In `MenuBarController.showContextMenu()`, replace

```swift
            infoItem.isEnabled = false
            menu.addItem(infoItem)
            menu.addItem(NSMenuItem.separator())
```

with

```swift
            infoItem.isEnabled = false
            menu.addItem(infoItem)
            if LidSleepController.shared.state == .on {
                let lidItem = NSMenuItem(
                    title: String(localized: "Closed-lid mode is on"),
                    action: nil,
                    keyEquivalent: ""
                )
                lidItem.isEnabled = false
                menu.addItem(lidItem)
            }
            menu.addItem(NSMenuItem.separator())
```

- [ ] **Step 5: Preferences UI**

In `src/Caffeine/Classes/Views/PreferencesView.swift`:

(a) Below `@State private var loginManager = LaunchAtLoginManager.shared` add:

```swift
    @State private var lidSleep = LidSleepController.shared
```

(b) Below `@AppStorage(PreferenceKeys.allowLidClose) private var allowLidClose = false` add:

```swift
    @AppStorage(PreferenceKeys.lidSleepBatteryThreshold)
    private var lidSleepBatteryThreshold = LidSleepController.defaultBatteryThreshold
```

(c) Replace

```swift
                Text("Works on AC power. On battery, macOS may still sleep when the lid is closed.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 20)
```

with

```swift
                Text("Works on battery too. Requires Touch ID or your password each time Caffeine activates.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 20)

                HStack(spacing: 8) {
                    Text("Restore sleep on battery below:")
                        .font(.system(size: 13))

                    Picker("", selection: self.$lidSleepBatteryThreshold) {
                        ForEach([10, 20, 30, 50], id: \.self) { percent in
                            Text(Double(percent) / 100, format: .percent).tag(percent)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 90)

                    Spacer()
                }
                .padding(.leading, 20)
                .disabled(!self.allowLidClose)

                if let failure = self.lidSleep.lastFailure {
                    Text(
                        failure == .lowBattery
                            ? LocalizedStringKey("Closed-lid mode was turned off because the battery is low.")
                            : LocalizedStringKey("Closed-lid mode on battery wasn't enabled.")
                    )
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .padding(.leading, 20)
                }
```

- [ ] **Step 6: Build and run all tests**

```bash
xcodebuild -project src/Caffeine.xcodeproj -scheme Caffeine -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "warning:|error:|BUILD" | grep -v appintents
swift test 2>&1 | grep -E "Executed .* tests" | tail -1
scripts/integration-test.sh 2>&1 | tail -1
```
Expected: `** BUILD SUCCEEDED **` with no warnings; `Executed 58 tests, with 0 failures`; `==> Integration checks passed` (the existing lid-closed/lid-open cases must not prompt: `shouldEngageLidSleep` is false for them).

- [ ] **Step 7: Changelog**

Under `## [Unreleased]` in `CHANGELOG.md`, add an `### Added` section above `### Changed`:

```markdown
### Added

- "Allow Mac to run with lid closed" now also works on battery. Each time Caffeine activates with it on, confirm with Touch ID (or your password). The first time, Caffeine asks for your administrator password once to install a rule that only allows turning lid-close sleep on and off.
- "Restore sleep on battery below" setting (10–50 %, default 20 %): on battery, closed-lid mode turns itself off at that level, and a Mac with the lid already closed goes to sleep.
- Normal sleep is restored when Caffeine is deactivated, quits, is killed with `kill`/`killall`, or — after a crash — the next time it starts.
- The Caffeine menu shows "Closed-lid mode is on" while it is active.
```

- [ ] **Step 8: Format and commit**

```bash
swiftformat .
git add src/Caffeine/Classes CHANGELOG.md
git commit -m "Wire closed-lid mode on battery into the app

Engage on activation (Touch ID each time, one-time setup alert), restore on
deactivate/toggle-off/quit, crash recovery at launch, SIGTERM routed to a
normal termination, battery threshold picker and failure text in
Preferences, status line in the menu."
```

---

### Task 7: Integration test and documentation

**Files:**
- Modify: `scripts/integration-test.sh`
- Modify: `README.md`, `README.zh-Hant.md`, `AGENTS.md`

**Interfaces:** Consumes the DEBUG hook `CA_TEST_AUTOACTIVATE=lid-battery` and SIGTERM handling from Task 6.

- [ ] **Step 1: Add helpers and the lid-battery cases to the integration script**

In `scripts/integration-test.sh`, replace the `cleanup()` function and the `trap cleanup EXIT` line with:

```bash
RULE=/etc/sudoers.d/caffeine-lid
LID_TEST_TOUCHED_SLEEP=0

# Prints "Yes" or "No": the SleepDisabled (pmset disablesleep) setting.
sleep_disabled_value() {
    ioreg -rn IOPMrootDomain -d 1 | awk -F'= ' '/"SleepDisabled"/ { print $2; exit }'
}

# Waits up to 30 s for SleepDisabled to equal $1 ("Yes"/"No").
wait_for_sleep_disabled() {
    local want="$1" elapsed=0
    while ((elapsed < 30)); do
        [[ "$(sleep_disabled_value)" == "$want" ]] && return 0
        sleep 1
        elapsed=$((elapsed + 1))
    done
    return 1
}

cleanup() {
    if [[ -n "$APP_PID" ]]; then
        kill "$APP_PID" 2>/dev/null || true
        wait "$APP_PID" 2>/dev/null || true
    fi
    # Never leave the Mac unable to sleep because a check failed midway.
    if [[ "$LID_TEST_TOUCHED_SLEEP" == 1 && "$(sleep_disabled_value)" == "Yes" ]]; then
        sudo -n /usr/bin/pmset disablesleep 0 || echo "WARN: run 'sudo pmset disablesleep 0' manually"
    fi
}
trap cleanup EXIT
```

Then replace the last three lines of the script (the two `run_case` lines and the final `echo`) with:

```bash
run_case "lid-closed" "PreventUserIdleDisplaySleep PreventUserIdleSystemSleep PreventSystemSleep"
run_case "lid-open"   "PreventUserIdleDisplaySleep PreventUserIdleSystemSleep" "PreventSystemSleep"

run_lid_battery_cases() {
    if [[ ! -e "$RULE" ]]; then
        echo "==> SKIP lid-battery cases: $RULE not installed (enable closed-lid mode once in the app)"
        return 0
    fi
    if [[ "$(sleep_disabled_value)" == "Yes" ]]; then
        echo "==> SKIP lid-battery cases: SleepDisabled is already on (set by something else)"
        return 0
    fi
    LID_TEST_TOUCHED_SLEEP=1

    echo "==> Case: CA_TEST_AUTOACTIVATE=lid-battery (quit restores sleep)"
    CA_TEST_AUTOACTIVATE=lid-battery "$BINARY" &
    APP_PID=$!
    wait_for_sleep_disabled Yes || { echo "FAIL: SleepDisabled never turned on"; return 1; }
    echo "    ok: SleepDisabled on while active"
    kill "$APP_PID"
    wait "$APP_PID" 2>/dev/null || true
    APP_PID=""
    wait_for_sleep_disabled No || { echo "FAIL: SleepDisabled still on after SIGTERM"; return 1; }
    echo "    ok: SleepDisabled restored on termination"

    echo "==> Case: crash recovery (kill -9, relaunch restores sleep)"
    CA_TEST_AUTOACTIVATE=lid-battery "$BINARY" &
    APP_PID=$!
    wait_for_sleep_disabled Yes || { echo "FAIL: SleepDisabled never turned on"; return 1; }
    kill -9 "$APP_PID"
    wait "$APP_PID" 2>/dev/null || true
    APP_PID=""
    [[ "$(sleep_disabled_value)" == "Yes" ]] || { echo "FAIL: expected SleepDisabled to survive a crash"; return 1; }
    CA_TEST_AUTOACTIVATE=lid-open "$BINARY" &
    APP_PID=$!
    wait_for_sleep_disabled No || { echo "FAIL: relaunch did not restore SleepDisabled"; return 1; }
    echo "    ok: relaunch restored SleepDisabled after crash"
    kill "$APP_PID"
    wait "$APP_PID" 2>/dev/null || true
    APP_PID=""
}
run_lid_battery_cases

echo "==> Integration checks passed"
```

- [ ] **Step 2: Run the integration test**

Run: `scripts/integration-test.sh 2>&1 | tail -12`
Expected, without the rule installed: the two existing cases pass, then `==> SKIP lid-battery cases: /etc/sudoers.d/caffeine-lid not installed …`, then `==> Integration checks passed`.
Expected, with the rule installed: additionally `ok: SleepDisabled on while active`, `ok: SleepDisabled restored on termination`, `ok: relaunch restored SleepDisabled after crash`. Afterwards `ioreg -rn IOPMrootDomain -d 1 | grep '"SleepDisabled"'` shows `No`.

- [ ] **Step 3: Update README.md**

In `README.md`:

(a) In the intro paragraph, replace `adds an **"Allow Mac to run with lid closed"** option (Amphetamine-parity on AC power)` with `adds an **"Allow Mac to run with lid closed"** option that works on AC power and on battery`.

(b) In the Features table, replace the `Launch at Login` row's `Uses `SMAppService`, sandbox-safe, no helper.` with `Uses `SMAppService`, no helper.`, and replace the whole `Allow Mac to run with lid closed` row with:

```markdown
| **Allow Mac to run with lid closed** *(new)* | Preferences → *Allow Mac to run with lid closed*. Keeps a portable Mac running with the lid closed — on AC power **and on battery**. Confirm with Touch ID each time Caffeine activates; sleep is restored automatically. |
```

(c) Replace the whole `### Allow Mac to run with lid closed` section (from that heading up to, not including, `## Languages`) with:

````markdown
### Allow Mac to run with lid closed

Switch on **Allow Mac to run with lid closed**, then activate Caffeine (click the cup). You can now close the lid and the Mac keeps running — on AC power or on battery. Useful for downloads, long renders, or streaming to an external display while the laptop is shut.

**First time:** Caffeine explains what it's about to do, then macOS asks for your administrator password **once**. Caffeine installs `/etc/sudoers.d/caffeine-lid`, a rule that only lets it run `pmset disablesleep 0` and `pmset disablesleep 1` — nothing else.

**Every activation:** confirm with Touch ID (or your password). If you cancel, Caffeine still activates, and lid-closed operation works on AC power only.

**Sleep is always restored** when you deactivate Caffeine, when its timer ends, when you quit it (including `killall Caffeine`), and — if it crashed — the next time it starts. On battery, it also turns off at the level set in **Restore sleep on battery below** (default 20 %); if the lid is already closed, the Mac then goes to sleep.

> ⚠️ While closed-lid mode is on, the Mac won't sleep at all — don't leave it running in a bag.

To check the setting in Terminal (`Yes` while closed-lid mode is on):

```bash
ioreg -rn IOPMrootDomain -d 1 | grep '"SleepDisabled"'
```

To remove the rule (Caffeine will ask again next time you use the feature):

```bash
sudo rm /etc/sudoers.d/caffeine-lid
```

If sleep ever stays disabled (e.g. Caffeine was deleted while closed-lid mode was on):

```bash
sudo pmset disablesleep 0
```
````

- [ ] **Step 4: Update README.zh-Hant.md**

In `README.zh-Hant.md`:

(a) In the intro paragraph, replace `新增了 **「闔蓋時保持運作」**（在接通電源時可達到 Amphetamine 等價效果）` with `新增了 **「闔蓋時保持運作」**（接通電源或使用電池時都有效）`.

(b) Replace the whole `闔蓋時保持運作` Features-table row with:

```markdown
| **闔蓋時保持運作** *(新)* | 偏好設定 → *闔蓋時保持運作*。讓筆電闔上蓋子後繼續運作 — **接通電源或使用電池都可以**。每次啟用 Caffeine 時用 Touch ID 確認，睡眠設定會自動還原。 |
```

(c) Replace the whole `### 闔蓋時保持運作` section (up to, not including, `## 支援的語言`) with:

````markdown
### 闔蓋時保持運作

開啟 **闔蓋時保持運作**，然後啟用 Caffeine（點杯子）。之後你可以闔上蓋子，Mac 會繼續執行 — 接通電源或使用電池都行。適合下載中、長時間轉檔，或把筆電當主機接外接螢幕時闔起來放著。

**第一次使用：** Caffeine 會先說明接下來的動作，然後 macOS 會要求輸入**一次**管理者密碼。Caffeine 會安裝 `/etc/sudoers.d/caffeine-lid`，這條規則只允許它執行 `pmset disablesleep 0` 和 `pmset disablesleep 1`，其他一概不行。

**每次啟用：** 用 Touch ID（或密碼）確認。如果取消，Caffeine 仍會啟用，但闔蓋運作只在接通電源時有效。

**睡眠一定會還原**：停用 Caffeine、計時結束、結束 Caffeine（包含 `killall Caffeine`），以及當機後下次啟動時。使用電池時，電量降到 **電池電量低於此值時恢復睡眠** 的設定值（預設 20%）也會自動關閉；如果此時蓋子已經闔上，Mac 會直接進入睡眠。

> ⚠️ 闔蓋模式開啟時，Mac 完全不會睡眠 — 不要讓它在包包裡繼續運作。

在終端機檢查目前設定（闔蓋模式開啟時顯示 `Yes`）：

```bash
ioreg -rn IOPMrootDomain -d 1 | grep '"SleepDisabled"'
```

移除規則（下次使用此功能時 Caffeine 會再詢問一次）：

```bash
sudo rm /etc/sudoers.d/caffeine-lid
```

如果睡眠一直沒有恢復（例如在闔蓋模式開啟時刪除了 Caffeine）：

```bash
sudo pmset disablesleep 0
```
````

- [ ] **Step 5: Update AGENTS.md**

In `AGENTS.md`:

(a) In `## Tech Stack`, add a bullet after the **Minimum Deployment** line:

```markdown
- **Not sandboxed** (Hardened Runtime only): closed-lid mode on battery runs `sudo -n /usr/bin/pmset disablesleep 0|1`
  through the sudoers rule `/etc/sudoers.d/caffeine-lid` (see `LidSleepController`)
```

(b) In `## Testing`, add a bullet at the end:

```markdown
- `scripts/integration-test.sh` exercises closed-lid mode on battery (including crash recovery) only when
  `/etc/sudoers.d/caffeine-lid` exists; otherwise those cases are skipped. The DEBUG-only
  `CA_TEST_AUTOACTIVATE=lid-battery` hook auto-approves the Touch ID step.
```

- [ ] **Step 6: Final verification**

```bash
xcodebuild -project src/Caffeine.xcodeproj -scheme Caffeine -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "warning:|error:|BUILD" | grep -v appintents
swift test 2>&1 | grep -E "Executed .* tests" | tail -1
scripts/integration-test.sh 2>&1 | tail -1
bash -n scripts/integration-test.sh && echo "script syntax ok"
```
Expected: `** BUILD SUCCEEDED **` with no warnings; `Executed 58 tests, with 0 failures`; `==> Integration checks passed`; `script syntax ok`.

- [ ] **Step 7: Format and commit**

```bash
swiftformat .
git add scripts/integration-test.sh README.md README.zh-Hant.md AGENTS.md
git commit -m "Add closed-lid battery integration cases and document the feature"
```
