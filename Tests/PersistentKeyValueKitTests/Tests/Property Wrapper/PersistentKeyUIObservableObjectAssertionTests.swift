//
//  PersistentKeyUIObservableObjectAssertionTests.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 9/15/26.
//

#if os(macOS) && DEBUG

import Darwin
import Foundation
import PersistentKeyValueKit
import XCTest

final class PersistentKeyUIObservableObjectAssertionTests: XCTestCase {
    // MARK: Tests

    @MainActor
    func test_nilStoreWriteAssertsInDebug() throws {
        if ProcessInfo.processInfo.environment["PKVK_ASSERTION_CHILD"] == "1" {
            let key = PersistentKey("key:\(#function)", defaultValue: 0)
            let observer = PersistentKeyUIObservableObject(store: nil, key: key)

            observer.value = 1
            return
        }

        let fileManager = FileManager.default
        let temporaryDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("PersistentKeyValueKit-Assertion-\(UUID().uuidString)")

        try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)

        defer {
            try? fileManager.removeItem(at: temporaryDirectory)
        }

        let stdoutURL = temporaryDirectory.appendingPathComponent("stdout")
        let stderrURL = temporaryDirectory.appendingPathComponent("stderr")
        fileManager.createFile(atPath: stdoutURL.path, contents: nil)
        fileManager.createFile(atPath: stderrURL.path, contents: nil)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = [
            "xctest",
            "-XCTest",
            "PersistentKeyValueKitTests.PersistentKeyUIObservableObjectAssertionTests/test_nilStoreWriteAssertsInDebug",
            Bundle(for: Self.self).bundleURL.path,
        ]

        var environment = ProcessInfo.processInfo.environment
        environment["PKVK_ASSERTION_CHILD"] = "1"

        if let profilePath = environment["LLVM_PROFILE_FILE"] {
            let profileDirectory = URL(fileURLWithPath: profilePath).deletingLastPathComponent()
            environment["LLVM_PROFILE_FILE"] = profileDirectory
                .appendingPathComponent("assertion-%p%c.profraw")
                .path
        }

        process.environment = environment
        let stdout = try FileHandle(forWritingTo: stdoutURL)

        defer {
            try? stdout.close()
        }

        let stderrHandle = try FileHandle(forWritingTo: stderrURL)

        defer {
            try? stderrHandle.close()
        }

        process.standardOutput = stdout
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
            if process.isRunning {
                process.terminate()
            }

            if termination.wait(timeout: .now() + 5) != .success, process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }

            guard termination.wait(timeout: .now() + 5) == .success else {
                XCTFail("Assertion child process termination was not confirmed")
                return XCTFail("Assertion child process timed out")
            }

            return XCTFail("Assertion child process timed out")
        }

        let stderr = try String(contentsOf: stderrURL, encoding: .utf8)

        XCTAssertEqual(process.terminationReason, .uncaughtSignal)
        XCTAssertTrue(stderr.contains("Store should always be set on initialization or immediately after."))
    }
}

#endif
