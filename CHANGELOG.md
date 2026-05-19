# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
