# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- With "Allow Mac to run with lid closed" on, the built-in screen now turns off when you close the lid instead of staying lit under it. An external display, if connected, is left on.
- After closed-lid mode ends with the lid already closed, the Mac now goes to sleep unless an external display is connected (it previously could stay awake because the lit built-in screen counted as an active display).

## [1.8.0] - 2026-10-02

### Added

- "Allow Mac to run with lid closed" now also works on battery. Each time you activate Caffeine with it on, confirm with Touch ID (or your password). Automatic activation at launch skips this, so logging in never shows a prompt; lid-closed operation then works on AC power only until you activate Caffeine yourself. The first time, Caffeine asks for your administrator password once to install a rule that only allows turning lid-close sleep on and off.
- "Restore sleep on battery below" setting (10–50 %, default 20 %): on battery, closed-lid mode turns itself off below that level, and a Mac with the lid already closed goes to sleep.
- Normal sleep is restored when Caffeine is deactivated, its timer ends, it quits, it is killed with `kill`/`killall`, or — after a crash — the next time it starts. If the lid is already closed (and no external display is in use), the Mac then goes to sleep. If sleep can't be restored, Preferences says how to fix it.
- The Caffeine menu shows "Closed-lid mode is on" while it is active.
- "Allow Mac to run with lid closed" can now be switched on and off directly from the Caffeine menu (right-click the menu bar icon), without opening Preferences.

### Changed

- The bundle identifier is now `io.github.bubbleee030.caffeine`, so this fork no longer shares settings with the original Caffeine. Preferences, "Launch at Login" and the Accessibility permission for "Keep apps active" need to be set up again once.
- Caffeine is no longer sandboxed, so it can turn off lid-close sleep on battery (see "Allow Mac to run with lid closed"). Previous settings are not carried over.

### Fixed

- "Check for Updates…" now checks this fork's own update feed. Previously it checked the original Caffeine's feed and could replace this fork with the original app.
- "Keep apps active" no longer moves the pointer to the wrong position on setups with multiple displays of different heights.
- "Keep apps active" could keep simulating activity after Caffeine was deactivated if it was turned off immediately after being turned on.

## [1.7.0] - 2026-05-19

### Added

- "Launch at Login" preference, backed by `SMAppService.mainApp`.
- "Allow Mac to run with lid closed" preference. When enabled, Caffeine additionally holds a `kIOPMAssertionTypePreventSystemSleep` assertion so a portable Mac on AC power keeps running with the lid closed.
- Traditional Chinese (zh-Hant) localization.
- Traditional Chinese README (`README.zh-Hant.md`) with a step-by-step tutorial for the two new toggles.
- Swift Package (`Package.swift`) + `swift test` unit tests covering the new launch-item and power-assertion wiring.
- `scripts/integration-test.sh` that builds the app and verifies `pmset -g assertions` reflects the expected types.

### Changed

- Sleep prevention now also holds `kIOPMAssertPreventUserIdleSystemSleep` (previously display-idle only), so the whole system stays awake during idle — not just the display.
- Bumped the IOPMAssertion timeout from 8 s to 30 s so the 10 s refresh window always overlaps (the previous values left a 2 s gap every cycle).
- Rewrote `README.md` to point at this fork's releases and issue tracker; removed third-party support and download URLs.
- Improved Ukrainian translation.

### Fixed

- Timer no longer stays active and shows negative seconds after the Mac sleeps past the activation period.

## [1.6.3] - 2026-01-26

### Added

- Ukrainian translation.

### Fixed

- Activity simulation now properly resets the system idle timer.

## [1.6.2] - 2025-12-14

### Added

- Optional "Keep apps active" preference that simulates activity to prevent apps from going idle.

### Fixed

- Corrected the Control-click instruction symbol.

## [1.6.1] - 2025-11-13

### Fixed

- Menu bar icon tinting.

## [1.6.0] - 2025-11-12

### Added

- Rewritten in SwiftUI.
- Automatic update reminders via Sparkle.
- App accent color and category.

### Changed

- Updated the icon for Tahoe with a static gradient.
- Repositioned menu items.

### Fixed

- Entitlements.
- Deprecation warnings.
- Typo on the preferences screen.

## [1.5.3] - 2025-06-25

### Added

- Control-click is now treated the same as a right-click.

## [1.5.2] - 2025-05-23

### Fixed

- Default duration is now respected.

## [1.5.1] - 2025-03-03

### Fixed

- Preferences window no longer appears unexpectedly on launch.

## [1.5.0] - 2025-01-22

### Added

- Automatic updates via Sparkle.

### Changed

- Migrated the project to Swift.
- Updated for macOS Sequoia.

## [1.4.0] - 2023-10-17

### Changed

- Updated icon for macOS Sonoma.

## [1.3.0] - 2023-10-17

### Added

- Japanese localization, plus localizations with dynamic layout support.
- Preference to deactivate Caffeine when the device is manually put to sleep.
- Sonoma-styled app icon.
- GitHub sponsorship support.

### Changed

- Refactored the preferences window.

### Fixed

- Deactivating the app now reliably releases the system sleep assertion.
- App icon drop shadow.
- View autoresizing.

## [1.1.3] - 2020-05-12

### Added

- Initial public release.
