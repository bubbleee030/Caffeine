# Caffeine - AGENTS.md

## Project Overview
macOS menu bar app that prevents your Mac from sleeping.

This repository is a fork (`bubbleee030/Caffeine`) of `domzilla/Caffeine`. Its bundle identifier is
`io.github.bubbleee030.caffeine` (upstream uses `net.domzilla.caffeine`), so the two apps keep separate preferences,
login items and privacy permissions.

## Tech Stack
- **Language**: Swift 5 language mode, with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and
  `SWIFT_APPROACHABLE_CONCURRENCY = YES` (everything in the app target is main-actor isolated unless marked otherwise)
- **UI Framework**: SwiftUI + AppKit (`NSStatusItem` menu bar item, `NSHostingController` preferences window)
- **Dependencies** (Swift Package Manager, referenced from the Xcode project):
  - [Sparkle](https://github.com/sparkle-project/Sparkle) — updates
  - [DZFoundation](https://github.com/domzilla/DZFoundation) — debug logging
- **Minimum Deployment**: macOS 14.6
- **Project**: `src/Caffeine.xcodeproj`

## Repository Layout
```
src/Caffeine/Classes/      App sources (File System Synchronized Group)
  Models/                  Power assertions, login item, activity simulation
  ViewModels/              CaffeineViewModel (activation state, timers, preference keys)
  Views/                   MenuBarController (status item + menu), PreferencesView
src/Caffeine/Resources/    Assets, Info.plist, entitlements, *.lproj (File System Synchronized Group)
Package.swift              Side package so `swift test` can unit-test model code (see Testing)
Tests/CaffeineCoreTests/   XCTest unit tests for the side package
scripts/                   integration-test.sh, reset.sh
```

## Xcode Project Files (DO NOT TOUCH)
- **Never edit Xcode project files** (`.xcodeproj`, `.xcworkspace`, `project.pbxproj`, `.xcsettings`, schemes, etc.)
- Only the user edits project settings, build phases, schemes, targets and package references, manually in Xcode
- If a change needs a project edit (new target, build setting, new package dependency), **stop and tell the user**
- Use `xcodebuild` for building only — never for project manipulation
- **Exception**: only proceed if the user gives explicit permission for a specific edit

`src/Caffeine/Classes/` and `src/Caffeine/Resources/` are **File System Synchronized Groups** (Xcode 16+), so files in
them can be freely created, moved, renamed and deleted; Xcode picks the changes up without a project edit.

## Build, Test & Format
The root `Package.swift` shadows the Xcode project, so `xcodebuild` **must** be given `-project` explicitly:
```bash
# Build the app
xcodebuild -project src/Caffeine.xcodeproj -scheme Caffeine -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO

# Unit tests (side Swift package — the Xcode project has no test target)
swift test

# Integration test: builds the app, runs it with a DEBUG auto-activate hook and checks `pmset -g assertions`
scripts/integration-test.sh

# Format (mandatory after a successful build, before committing)
swiftformat .
```

## Testing
- **No manual QA.** Verify changes with `swift test`, a successful `xcodebuild` build, and `scripts/integration-test.sh`.
- `Package.swift` compiles an explicit list of files from `src/Caffeine/Classes/Models` into a `CaffeineCore` library.
  When adding testable model code, add the file to that `sources:` list.
- Hardware and OS boundaries are hidden behind protocols (`PowerAssertionBackend`, `LaunchItemBackend`) so tests can
  inject fakes. Follow the same pattern for new system integrations.
- Model files shared with the package must not assume the app's default MainActor isolation: mark types `@MainActor`
  explicitly and don't reference main-actor `shared` singletons from default arguments.
- `LocalizationTests` fails if any locale is missing a key — add new keys to its `expectedKeys` list.

## Changelog (MANDATORY)
All important user-facing changes (fixes, additions, removals, changes) must be recorded under `## [Unreleased]` in
`CHANGELOG.md`. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning:
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Localization (MANDATORY)
- All user-facing strings must be localized (`String(localized:)` in code, `Text("key")` in SwiftUI)
- Every key must be present in all 14 locales: `de en es fr it ja ko nl pt pt-BR ru uk zh-Hans zh-Hant`
  (`src/Caffeine/Resources/<locale>.lproj/Localizable.strings`)
- Match the formality already used in each locale (e.g. informal "du" in German, "vous" in French — as Apple does)
  and Apple's macOS terminology for that language; keep terms consistent with existing strings

## Logging (MANDATORY)
Use **DZFoundation** for debug logging; both functions are no-ops in Release builds:
```swift
import DZFoundation

DZLog("Starting fetch")   // 🔶 fetchData() 42: Starting fetch
DZErrorLog(error)         // ❌ MyFile.swift:45 fetchData() ERROR: Network unavailable (only if error is non-nil)
```
Do **not** use `print()`, `os.Logger` or `NSLog`.

Files that are also compiled by `Package.swift` can't see DZFoundation (the side package doesn't depend on it), so
guard the import and calls with `#if canImport(DZFoundation)`.

## Code Style
- SwiftFormat config lives in `.swiftformat` (4-space indent, explicit `self.`, K&R braces, trailing commas, 120 cols)
- Prefer native SwiftUI patterns over MVVM boilerplate; prefer `@Observable` over `ObservableObject` for new types
- Use `async/await` and the `.task` modifier for async work; avoid Combine unless it's genuinely the simplest option
- Apple API reference: <https://developer.apple.com/documentation>
