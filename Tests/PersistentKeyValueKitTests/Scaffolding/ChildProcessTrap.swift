#if os(macOS)

import Darwin
import Foundation
import XCTest

/// Runs one test in a child `xctest` process and asserts that it terminates with a trap whose message contains
/// `message`.
///
/// The child runs the same test method with ``isRunningInTrapChildProcess`` set, so the method performs the trapping
/// operation instead of calling this function again. The child writes coverage to its own continuous-mode profile so
/// trapped code still counts toward coverage.
enum ChildProcessTrap {
    private static let environmentKey = "PKVK_TRAP_CHILD"

    // MARK: Internal Static Interface

    static var isRunningInTrapChildProcess: Bool {
        ProcessInfo.processInfo.environment[environmentKey] == "1"
    }

    static func assertTraps(
        test: String,
        in testCase: XCTestCase,
        message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let fileManager = FileManager.default
        let temporaryDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("PersistentKeyValueKit-Trap-\(UUID().uuidString)")

        try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)

        defer {
            try? fileManager.removeItem(at: temporaryDirectory)
        }

        let stderrURL = temporaryDirectory.appendingPathComponent("stderr")
        fileManager.createFile(atPath: stderrURL.path, contents: nil)

        let testName = test.replacingOccurrences(of: "()", with: "")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = [
            "xctest",
            "-XCTest",
            "PersistentKeyValueKitTests.\(String(describing: type(of: testCase)))/\(testName)",
            Bundle(for: type(of: testCase)).bundleURL.path,
        ]

        var environment = ProcessInfo.processInfo.environment
        environment[environmentKey] = "1"

        if let profilePath = environment["LLVM_PROFILE_FILE"] {
            let profileDirectory = URL(fileURLWithPath: profilePath).deletingLastPathComponent()
            environment["LLVM_PROFILE_FILE"] = profileDirectory
                .appendingPathComponent("trap-%p%c.profraw")
                .path
        }

        process.environment = environment
        let stderrHandle = try FileHandle(forWritingTo: stderrURL)

        defer {
            try? stderrHandle.close()
        }

        process.standardOutput = FileHandle.nullDevice
        process.standardError = stderrHandle

        let termination = DispatchGroup()
        termination.enter()
        process.terminationHandler = { _ in
            termination.leave()
        }

        do {
            try process.run()
        } catch {
            termination.leave()
            throw error
        }

        guard termination.wait(timeout: .now() + 10) == .success else {
            process.terminate()

            if termination.wait(timeout: .now() + 5) != .success {
                kill(process.processIdentifier, SIGKILL)
            }

            return XCTFail("Trap child process timed out", file: file, line: line)
        }

        let stderr = try String(contentsOf: stderrURL, encoding: .utf8)

        XCTAssertEqual(process.terminationReason, .uncaughtSignal, file: file, line: line)
        XCTAssertTrue(stderr.contains(message), stderr, file: file, line: line)
    }
}

#endif
