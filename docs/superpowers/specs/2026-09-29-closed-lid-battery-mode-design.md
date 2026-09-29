# Closed-Lid Mode on Battery — Design

**Date:** 2026-09-29
**Status:** Draft, awaiting review
**Branch:** `feature/closed-lid-battery`

## Goal

Let a portable Mac keep running with the lid closed **on battery**, not just on AC power, while Caffeine is active and
"Allow Mac to run with lid closed" is on. Each engagement is confirmed with Touch ID (password fallback), and normal
sleep is always restored — including after a crash and when the battery runs low.

Inspired by the closed-lid mode in [vorssaint-utils](https://github.com/vorssaint/vorssaint-utils). That project is
GPL-3.0 and Caffeine is MIT, so the approach is reimplemented from scratch; no code is copied.

## Background

- Caffeine 1.7.0 holds `kIOPMAssertionTypePreventSystemSleep` when the toggle is on. That keeps a Mac awake with the
  lid closed **only on AC power**; on battery, macOS sleeps when the lid closes.
- `pmset disablesleep 1` (the `SleepDisabled` power setting) disables system sleep entirely, including lid-close sleep
  on battery. It requires root and is **system-wide and persistent**: it survives the app quitting, crashing, and
  reboots until someone runs `pmset disablesleep 0`.
- A sandboxed app cannot run `sudo` or `do shell script … with administrator privileges`.

## Non-goals

- A privileged helper daemon (`SMAppService.daemon`). It would keep the sandbox but needs a new Xcode target. The
  `SleepSettingBackend` protocol leaves room to swap one in later.
- Thermal monitoring beyond what macOS already does.
- An in-app "uninstall" button for the sudoers rule (documented in README instead).

## Decisions

| Topic | Decision |
|---|---|
| Privilege mechanism | Remove the App Sandbox; run `sudo -n /usr/bin/pmset disablesleep 0/1` via a scoped sudoers rule |
| Touch ID | Prompted **every time** lid mode engages (each activation with the toggle on) |
| Low battery | On battery at or below a threshold (default 20 %, choices 10/20/30/50 %), restore normal sleep only; the Caffeine session itself continues |
| Update feed | Fork gets its own Sparkle appcast + EdDSA key (separate milestone, blocked on the user's public key) |

## Architecture

### 1. Remove the App Sandbox

`src/Caffeine/Resources/Caffeine.entitlements` becomes an empty dict (Hardened Runtime stays on via build settings):

- remove `com.apple.security.app-sandbox`
- remove `com.apple.security.temporary-exception.mach-lookup.global-name` (Sparkle's sandbox XPC services)
- remove `com.apple.security.network.client`, `network.server`, `files.user-selected.read-only`

`Info.plist`: remove `SUEnableInstallerLauncherService` (only needed when sandboxed).

Side effect: preferences move from `~/Library/Containers/<bundle id>/…` to `~/Library/Preferences/`. No migration —
the planned bundle-ID change resets preferences anyway. Noted in CHANGELOG.

### 2. Components (all in `src/Caffeine/Classes/Models/`, `@MainActor`, compiled into the `CaffeineCore` test package)

```
LidSleepController ──▶ SleepSettingBackend   (pmset + sudoers)
        │          ──▶ UserAuthenticator     (Touch ID / password)
        │          ──▶ BatteryMonitor        (AC/battery, percent, lid state)
        └── persists `CALidSleepOverrideActive` in UserDefaults
```

**`SleepSettingBackend`** (protocol) — production: `PmsetSleepSettingBackend`

```swift
protocol SleepSettingBackend: AnyObject {
    /// `SleepDisabled` from `pmset -g`; nil if it couldn't be read.
    func isSleepDisabled() async -> Bool?
    /// `sudo -n /usr/bin/pmset disablesleep 0|1`. Throws if sudo refuses or pmset fails.
    func setSleepDisabled(_ disabled: Bool) async throws
    /// Whether `/etc/sudoers.d/caffeine-lid` exists. (`sudo -n -l` is not used: a cached sudo timestamp
    /// would make it succeed for any admin even without the rule.) A rule that exists but is refused
    /// at run time is handled by `setSleepDisabled` throwing.
    func isPasswordlessRuleInstalled() async -> Bool
    /// Installs the rule via one administrator prompt. Throws on cancel or failure.
    func installPasswordlessRule() async throws
}
```

Sudoers rule, written to `/etc/sudoers.d/caffeine-lid`:

```
# Installed by Caffeine — allows toggling lid-close sleep without a password.
<uid-name> ALL=(root) NOPASSWD: /usr/bin/pmset disablesleep 0, /usr/bin/pmset disablesleep 1
```

Install steps, as one `do shell script … with administrator privileges` invocation (single prompt): write the rule
to a temp file → `visudo -cf <tmp>` → `install -m 0440 -o root -g wheel <tmp> /etc/sudoers.d/caffeine-lid`. If
`visudo` rejects the file, nothing is installed. The user name is taken from `NSUserName()` and validated against
`^[A-Za-z0-9._-]+$` before it's interpolated; the rule text is built by a pure function so it can be unit-tested.
Processes are launched with `Process` and absolute paths (`/usr/bin/sudo`, `/usr/bin/pmset`), never via a shell string
built from user input.

**`UserAuthenticator`** (protocol) — production: `LocalAuthenticator`, using `LAContext.evaluatePolicy(
.deviceOwnerAuthentication, …)` (Touch ID, falls back to the login password; works on Macs without Touch ID).

```swift
protocol UserAuthenticator: AnyObject {
    func authenticate(reason: String) async -> Bool
}
```

**`BatteryMonitor`** (protocol) — production: `IOKitBatteryMonitor`, using `IOPSCopyPowerSourcesInfo` for the
snapshot, `IOPSNotificationCreateRunLoopSource` for changes, and `AppleClamshellState` on `IOPMrootDomain` for lid state.

```swift
struct PowerSnapshot: Equatable { var isOnBattery: Bool; var percent: Int? }
protocol BatteryMonitor: AnyObject {
    var snapshot: PowerSnapshot { get }
    var isLidClosed: Bool { get }
    var onChange: (() -> Void)? { get set }
    func sleepNow()   // IOPMSleepSystem
}
```

**`LidSleepController`** — state machine: `off → enabling → on → restoring → off`.

- `engage()` — called when a Caffeine session starts (or the toggle turns on mid-session):
  1. If the battery guard would trip right now, don't engage.
  2. If the sudoers rule is missing, run the one-time setup: show an explanatory alert, then
     `installPasswordlessRule()`. Cancel/failure → stay `off`, set `lastFailure`.
  3. `authenticate(reason:)`. Denied → stay `off`, set `lastFailure`.
  4. **Write `CALidSleepOverrideActive = true` before** calling `setSleepDisabled(true)`, so a crash mid-call can't
     leave an unrecorded override.
  5. Success → `on`. Failure → attempt restore, clear the flag, set `lastFailure`.
- `restore(synchronous:)` — `setSleepDisabled(false)`, then clear the flag. No authentication needed (restoring is
  always allowed). `synchronous: true` blocks up to 5 s, for use from `applicationWillTerminate`.
- `recoverOnLaunch()` — if the flag is set and `isSleepDisabled() == true`, restore; if the flag is set and sleep is
  already enabled, just clear the flag. A `SleepDisabled 1` that Caffeine didn't set (flag unset) is left alone.
- Battery guard — on each `BatteryMonitor.onChange` (and on engage): if `isOnBattery && percent <= threshold` while
  `on`, restore, then call `sleepNow()` if the lid is closed. It doesn't re-engage automatically when charging resumes;
  the next activation does.

`lastFailure` is surfaced to the UI (below) and logged with `DZErrorLog` under `#if canImport(DZFoundation)`.

### 3. Integration with existing code

- `SleepPreventionManager` is unchanged. The AC-only `PreventSystemSleep` assertion stays, so lid mode still works on
  AC if the user cancels Touch ID.
- `CaffeineViewModel`
  - `activate(...)`: after `preventSleep(allowLidClose:)`, if the toggle is on → `Task { await lidSleep.engage() }`.
  - `deactivate()` (manual, timer expiry, manual-sleep option) → `restore(synchronous: false)`.
  - `setAllowLidClose(_:)`: on → engage if active; off → restore.
  - `init` → `recoverOnLaunch()` before any auto-activation.
- `MenuBarController.cleanup()` (from `applicationWillTerminate`) → `restore(synchronous: true)`.
- Restore triggers, complete list: deactivate, timer expiry, quit, toggle off, low battery, launch recovery.

### 4. UI (`PreferencesView`, menu)

- The toggle label stays: "Allow Mac to run with lid closed".
- Its footnote becomes: "Works on battery too. Requires Touch ID or your password each time Caffeine activates."
- New row, enabled only when the toggle is on: "Restore sleep on battery below:" with a picker of 10 % / 20 % / 30 % /
  50 % (key `CALidSleepBatteryThreshold`, default 20).
- One-time setup alert: title "Allow closed-lid mode on battery?", body explaining the single-command admin rule and
  that it can be removed with `sudo rm /etc/sudoers.d/caffeine-lid`. Buttons: "Continue" / "Cancel".
- Context menu, while `on`: disabled info item "Closed-lid mode is on".
- Failure: footnote-style red text under the toggle, e.g. "Closed-lid mode on battery wasn't enabled." (Cleared on the
  next successful engage.)

All new strings are added to all 14 locales and to `LocalizationTests.expectedKeys`. Touch ID reason string:
"enable closed-lid mode" (macOS shows it as "Caffeine is trying to enable closed-lid mode").

### 5. Update feed (independent milestone)

- `SUFeedURL` → `https://raw.githubusercontent.com/bubbleee030/Caffeine/master/appcast.xml`
- `SUPublicEDKey` → the user's key from Sparkle's `generate_keys` (private key stays in their login Keychain)
- Add an `appcast.xml` with an empty channel, and document the release steps (`generate_appcast`/`sign_update`,
  commit appcast) in AGENTS.md.
- The user changes the bundle ID in Xcode (not part of this work — `.xcodeproj` is off-limits).

## Error handling summary

| Situation | Behavior |
|---|---|
| User cancels the setup prompt or Touch ID | Caffeine stays active; lid mode AC-only; failure text shown |
| `sudo -n` refuses (rule removed/altered) | Treated as missing rule → setup runs again on next engage |
| `pmset` fails enabling | Restore attempted, flag cleared, failure text shown |
| `pmset` fails restoring | Flag kept, so the next launch retries; logged |
| Crash / force quit while on | Next launch restores (flag set + `SleepDisabled 1`) |
| `SleepDisabled 1` set by someone else | Left untouched |

## Testing

No manual QA; each milestone ends green and is committed.

**Unit tests** (`swift test`, fakes for all three protocols):
- engage: flag persisted before the `setSleepDisabled(true)` call; denied auth → no backend call; missing rule →
  install then enable; install failure → `off` + `lastFailure`
- restore on each trigger; restore keeps the flag when the backend throws
- recoverOnLaunch: flag+disabled → restore; flag+enabled → clear only; no flag → untouched
- battery guard: trips only when on battery and ≤ threshold; calls `sleepNow()` only when the lid is closed; blocks engage
- sudoers rule builder: exact text; rejects invalid user names
- `pmset -g` parser: reads `SleepDisabled 0/1`; missing line → nil

**Integration** (`scripts/integration-test.sh`): new case `CA_TEST_AUTOACTIVATE=lid-battery` using a DEBUG-only
authenticator that always succeeds (compiled out of Release). It asserts `pmset -g` shows `SleepDisabled 1` while
active and `0` after the app is terminated. Skipped with a notice when `/etc/sudoers.d/caffeine-lid` doesn't
exist (rule not installed).

## Milestones

1. **M1 — Update feed**: Info.plist feed/key, `appcast.xml`, release docs. *Blocked on the user's public key.*
2. **M2 — Remove sandbox**: entitlements + Info.plist; build + existing tests + integration green.
3. **M3 — Lid sleep core**: protocols, production backends, `LidSleepController`, unit tests, add files to `Package.swift`.
4. **M4 — Wire-up + UI + localization**: view model, termination, preferences, menu, 14 locales.
5. **M5 — Integration + docs**: integration case, README (en + zh-Hant) incl. how to remove the rule, CHANGELOG.
