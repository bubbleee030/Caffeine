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
