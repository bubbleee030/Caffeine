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
