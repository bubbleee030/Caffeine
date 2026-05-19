//
//  LocalizationTests.swift
//  CaffeineCoreTests
//
//  Verifies that every shipped .lproj/Localizable.strings file parses and
//  contains the full key set, so any new user-facing string forces every
//  locale to be updated.
//

import Foundation
import XCTest

final class LocalizationTests: XCTestCase {
    /// Path to `src/Caffeine/Resources` resolved relative to this test source
    /// file so tests work no matter where the repo is checked out.
    private var resourcesURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // CaffeineCoreTests/
            .deletingLastPathComponent() // Tests/
            .deletingLastPathComponent() // repo root
            .appendingPathComponent("src/Caffeine/Resources")
    }

    /// Locales that ship in the app bundle.
    private let expectedLocales = [
        "de", "en", "es", "fr", "it", "ja", "ko",
        "nl", "pt", "pt-BR", "ru", "uk", "zh-Hans", "zh-Hant",
    ]

    /// Every key that PreferencesView, MenuBarController, or the model layer
    /// looks up via `String(localized:)`. Failure to find any of these in any
    /// locale is a build-break.
    private let expectedKeys: Set<String> = [
        // Activation durations
        "1 minute", "5 minutes", "10 minutes", "15 minutes", "30 minutes",
        "1 hour", "2 hours", "5 hours", "Indefinitely",
        // Status messages
        "Caffeine is active", "%d minutes", "%d seconds",
        // Menu items
        "Check for Updates...", "Preferences...", "About Caffeine", "Quit",
        // Preferences instructions
        "Caffeine is now running. You can find its icon in the right side of your menu bar. Click it to disable automatic sleep, click it again to enable automatic sleep.",
        "Right-click (or ⌃-click) the menu bar icon to show the Caffeine menu.",
        // Preferences labels
        "Default duration:",
        "Activate when starting Caffeine",
        "Deactivate when device goes to sleep manually",
        "Show this message when starting Caffeine",
        "Keep apps active",
        "Prevents apps from becoming inactive and the screen saver from starting.",
        "Launch at Login",
        "Allow Mac to run with lid closed",
        "Works on AC power. On battery, macOS may still sleep when the lid is closed.",
        "Close",
        // Menu additions
        "Activate for", "Welcome to Caffeine",
        // About credits
        "© 2006 Tomas Franzén\n© 2018 Michael Jones\n© 2022 Dominic Rodemer\n© 2026 @bubbleee030\n\nSource code:\nhttps://github.com/bubbleee030/Caffeine",
        // System messages
        "Caffeine prevents sleep",
    ]

    func testEveryLocaleParsesAndContainsAllKeys() {
        for locale in self.expectedLocales {
            let stringsURL = self.resourcesURL
                .appendingPathComponent("\(locale).lproj")
                .appendingPathComponent("Localizable.strings")

            guard FileManager.default.fileExists(atPath: stringsURL.path) else {
                XCTFail("Missing Localizable.strings for \(locale) at \(stringsURL.path)")
                continue
            }

            guard let dict = NSDictionary(contentsOf: stringsURL) as? [String: String] else {
                XCTFail("\(locale): failed to parse Localizable.strings as [String: String]")
                continue
            }

            let actualKeys = Set(dict.keys)
            let missing = self.expectedKeys.subtracting(actualKeys)
            XCTAssertTrue(
                missing.isEmpty,
                "\(locale) is missing \(missing.count) key(s): \(missing.sorted())"
            )
        }
    }

    func testTraditionalChineseLocaleExistsAndIsDistinctFromSimplified() {
        let hantURL = self.resourcesURL
            .appendingPathComponent("zh-Hant.lproj")
            .appendingPathComponent("Localizable.strings")
        let hansURL = self.resourcesURL
            .appendingPathComponent("zh-Hans.lproj")
            .appendingPathComponent("Localizable.strings")

        guard
            let hant = NSDictionary(contentsOf: hantURL) as? [String: String],
            let hans = NSDictionary(contentsOf: hansURL) as? [String: String] else
        {
            XCTFail("zh-Hant or zh-Hans failed to parse")
            return
        }

        XCTAssertEqual(hant.keys.sorted(), hans.keys.sorted(), "zh-Hant must cover the same keys as zh-Hans")

        // Beyond key parity, the two scripts must differ for the bulk of the
        // user-facing values. A single representative key isn't enough — it
        // could happen to translate identically in both scripts. Require that
        // at least half the values are non-identical across the two locales.
        let differingValues = self.expectedKeys.filter { hant[$0] != hans[$0] }
        let ratio = Double(differingValues.count) / Double(self.expectedKeys.count)
        XCTAssertGreaterThan(
            ratio, 0.5,
            "Only \(differingValues.count)/\(self.expectedKeys.count) keys differ between zh-Hant and zh-Hans — one of the locales is probably a copy of the other."
        )
    }
}
