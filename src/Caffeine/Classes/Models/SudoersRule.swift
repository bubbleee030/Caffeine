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
