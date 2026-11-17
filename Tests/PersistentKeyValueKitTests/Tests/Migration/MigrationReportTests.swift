import Foundation
import XCTest

@testable import PersistentKeyValueKit

final class MigrationReportTests: XCTestCase {
    // MARK: Tests

    func testCompletionErrorIsReportedAlongsideFailedCompletion() throws {
        let source = InMemoryPersistentKeyValueStore()
        let destination = InMemoryPersistentKeyValueStore()
        let recorder = MigrationFaultStore()
        let key = PersistentKey<Int>("key:\(#function)", defaultValue: 0)

        source.set(key, to: 1)
        recorder.failure = .commit
        let report = try source.copy(
            key,
            to: destination,
            onConflict: .overwriteDestination,
            tracking: .once(id: #function, recordedIn: recorder)
        )

        XCTAssertEqual(report.completion, .failed)
        XCTAssertEqual(report.completionError as? PersistentKeyMigrationError, .writeVerificationFailed)
        XCTAssertEqual(report.outcomes.map(\.status), [.copied])
        XCTAssertNil(report.outcomes[0].error)
        XCTAssertTrue(report.hasFailures)
        XCTAssertFalse(report.isComplete)
    }

    func testEmptyBatchWithTrackingRecordsMarker() throws {
        let source = InMemoryPersistentKeyValueStore()
        let destination = InMemoryPersistentKeyValueStore()
        let recorder = InMemoryPersistentKeyValueStore()

        let inDestination = try source.move(
            items: [],
            to: destination,
            onConflict: .keepBoth,
            tracking: .once(id: #function)
        )

        XCTAssertEqual(inDestination.completion, .recorded)
        XCTAssertTrue(inDestination.outcomes.isEmpty)
        XCTAssertTrue(destination.get(.isMigrationCompleted(id: #function)))
        XCTAssertNil(try source.migrationSnapshot(for: PersistentKey<Bool>.isMigrationCompleted(id: #function).id))

        let inRecorder = try source.copy(
            [],
            to: destination,
            onConflict: .keepDestination,
            tracking: .once(id: #function, recordedIn: recorder)
        )

        XCTAssertEqual(inRecorder.completion, .recorded)
        XCTAssertTrue(recorder.get(.isMigrationCompleted(id: #function)))

        let repeated = try source.copy(
            items: [],
            to: destination,
            onConflict: .keepDestination,
            tracking: .once(id: #function)
        )

        XCTAssertEqual(repeated.completion, .alreadyRecorded)
        XCTAssertTrue(repeated.isComplete)
    }

    func testOutcomeForKeyMatchesSourceKeyIdentifier() throws {
        let source = InMemoryPersistentKeyValueStore()
        let destination = InMemoryPersistentKeyValueStore()
        let old = PersistentKey<Int>("old:\(#function)", defaultValue: 0)
        let new = PersistentKey<Int>("new:\(#function)", defaultValue: 0)
        let plain = PersistentKey<String>("plain:\(#function)", defaultValue: "")
        let unrelated = PersistentKey<Int>("unrelated:\(#function)", defaultValue: 0)

        source.set(old, to: 1)
        let report = try source.copy(
            items: [.key(old, to: new), .key(plain)],
            to: destination,
            onConflict: .overwriteDestination,
            tracking: .once(id: #function)
        )

        XCTAssertEqual(report.outcome(for: old)?.status, .copied)
        XCTAssertEqual(report.outcome(for: old)?.destinationKeyID, new.id)
        XCTAssertEqual(report.outcome(for: plain)?.status, .sourceAbsent)
        XCTAssertEqual(report.outcome(for: plain)?.destinationKeyID, plain.id)
        XCTAssertNil(report.outcome(for: new))
        XCTAssertNil(report.outcome(for: unrelated))

        let skipped = try source.copy(
            items: [.key(old, to: new)],
            to: destination,
            onConflict: .overwriteDestination,
            tracking: .once(id: #function)
        )

        XCTAssertEqual(skipped.completion, .alreadyRecorded)
        XCTAssertNil(skipped.outcome(for: old))
    }

    func testOutcomeInitializersPreserveTheErrorInvariant() {
        let plain = PersistentKeyMigrationReport.Outcome(sourceKeyID: "a", status: .copied)

        XCTAssertEqual(plain.sourceKeyID, "a")
        XCTAssertEqual(plain.destinationKeyID, "a")
        XCTAssertEqual(plain.status, .copied)
        XCTAssertNil(plain.error)

        let mapped = PersistentKeyMigrationReport.Outcome(sourceKeyID: "a", destinationKeyID: "b", status: .moved)

        XCTAssertEqual(mapped.destinationKeyID, "b")

        let failed = PersistentKeyMigrationReport.Outcome(
            sourceKeyID: "a",
            destinationKeyID: "b",
            failedAt: .transform,
            error: PersistentKeyMigrationError.sourceChanged
        )

        XCTAssertEqual(failed.status, .failed(.transform))
        XCTAssertEqual(failed.destinationKeyID, "b")
        XCTAssertEqual(failed.error as? PersistentKeyMigrationError, .sourceChanged)

        let unmapped = PersistentKeyMigrationReport.Outcome(
            sourceKeyID: "a",
            failedAt: .cleanup,
            error: PersistentKeyMigrationError.removalVerificationFailed
        )

        XCTAssertEqual(unmapped.destinationKeyID, "a")
    }

    func testReportInitializersPreserveTheCompletionErrorInvariant() {
        let completions: [PersistentKeyMigrationReport.Completion] = [.alreadyRecorded, .recorded, .untracked]

        for completion in completions {
            let report = PersistentKeyMigrationReport(outcomes: [], completion: completion)

            XCTAssertEqual(report.completion, completion)
            XCTAssertNil(report.completionError)
            XCTAssertTrue(report.isComplete)
            XCTAssertFalse(report.hasFailures)
        }

        let failure = PersistentKeyMigrationReport.Outcome(
            sourceKeyID: "a",
            failedAt: .write,
            error: PersistentKeyMigrationError.writeVerificationFailed
        )
        let notRecorded = PersistentKeyMigrationReport(
            outcomes: [failure, .init(sourceKeyID: "b", status: .copied)],
            completion: .notRecorded
        )

        XCTAssertNil(notRecorded.completionError)
        XCTAssertTrue(notRecorded.hasFailures)
        XCTAssertFalse(notRecorded.isComplete)
        XCTAssertTrue(PersistentKeyMigrationReport(outcomes: [failure], completion: .untracked).hasFailures)

        let failed = PersistentKeyMigrationReport(
            outcomes: [.init(sourceKeyID: "a", status: .copied)],
            completionError: PersistentKeyMigrationError.writeVerificationFailed
        )

        XCTAssertEqual(failed.completion, .failed)
        XCTAssertEqual(failed.completionError as? PersistentKeyMigrationError, .writeVerificationFailed)
        XCTAssertEqual(failed.outcomes.count, 1)
    }

    func testStatusesAreHashable() {
        let stages: [PersistentKeyMigrationReport.FailureStage] = [
            .snapshot, .decode, .transform, .prepare, .write, .cleanup,
        ]
        let statuses: [PersistentKeyMigrationReport.Status] = [
            .copied, .discardedSource, .keptDestination, .keyDisabled, .moved, .sourceAbsent,
        ] + stages.map(PersistentKeyMigrationReport.Status.failed)
        let completions: [PersistentKeyMigrationReport.Completion] = [
            .alreadyRecorded, .failed, .notRecorded, .recorded, .untracked,
        ]

        XCTAssertEqual(Set(stages).count, 6)
        XCTAssertEqual(Set(statuses).count, 12)
        XCTAssertEqual(Set(completions).count, 5)
        XCTAssertEqual(PersistentKeyMigrationReport.Status.failed(.write), .failed(.write))
        XCTAssertNotEqual(PersistentKeyMigrationReport.Status.failed(.write), .failed(.cleanup))
    }

    func testThrowIfIncompleteThrowsExactlyWhenIncomplete() throws {
        let complete = PersistentKeyMigrationReport(
            outcomes: [.init(sourceKeyID: "a", status: .copied)],
            completion: .recorded
        )

        XCTAssertNoThrow(try complete.throwIfIncomplete())

        let reports = [
            PersistentKeyMigrationReport(
                outcomes: [
                    .init(
                        sourceKeyID: "a",
                        failedAt: .write,
                        error: PersistentKeyMigrationError.writeVerificationFailed
                    )
                ],
                completion: .untracked
            ),
            PersistentKeyMigrationReport(
                outcomes: [
                    .init(sourceKeyID: "a", failedAt: .decode, error: PersistentKeyValueConversionError.invalidValue)
                ],
                completion: .notRecorded
            ),
            PersistentKeyMigrationReport(outcomes: [], completionError: PersistentKeyMigrationError.destinationChanged),
        ]

        for report in reports {
            XCTAssertThrowsError(try report.throwIfIncomplete()) {
                guard let error = $0 as? PersistentKeyMigrationIncompleteError else {
                    return XCTFail("Expected PersistentKeyMigrationIncompleteError, got \($0)")
                }

                XCTAssertEqual(error.report.completion, report.completion)
                XCTAssertEqual(error.report.outcomes.map(\.status), report.outcomes.map(\.status))
                XCTAssertFalse(error.report.isComplete)
            }
        }
    }

    #if os(macOS) && DEBUG

    func test_alreadyRecordedCompletionWithOutcomesTraps() throws {
        if ChildProcessTrap.isRunningInTrapChildProcess {
            _ = PersistentKeyMigrationReport(
                outcomes: [.init(sourceKeyID: "a", status: .moved)],
                completion: .alreadyRecorded
            )
            return
        }

        let skipped = PersistentKeyMigrationReport(outcomes: [], completion: .alreadyRecorded)

        XCTAssertTrue(skipped.isComplete)

        try ChildProcessTrap.assertTraps(
            test: #function,
            in: self,
            message: "A report whose completion was already recorded cannot have outcomes."
        )
    }

    func test_failedCompletionWithFailedOutcomeTraps() throws {
        if ChildProcessTrap.isRunningInTrapChildProcess {
            _ = PersistentKeyMigrationReport(
                outcomes: [
                    .init(sourceKeyID: "a", failedAt: .write, error: PersistentKeyMigrationError.destinationChanged)
                ],
                completionError: PersistentKeyMigrationError.writeVerificationFailed
            )
            return
        }

        try ChildProcessTrap.assertTraps(
            test: #function,
            in: self,
            message: "A report whose completion failed cannot have a failed outcome."
        )
    }

    func test_failedCompletionWithoutErrorTraps() throws {
        if ChildProcessTrap.isRunningInTrapChildProcess {
            _ = PersistentKeyMigrationReport(outcomes: [], completion: .failed)
            return
        }

        try ChildProcessTrap.assertTraps(
            test: #function,
            in: self,
            message: "Use init(outcomes:completionError:) to create a report whose completion failed."
        )
    }

    func test_failedOutcomeWithoutErrorTraps() throws {
        if ChildProcessTrap.isRunningInTrapChildProcess {
            _ = PersistentKeyMigrationReport.Outcome(sourceKeyID: "a", status: .failed(.write))
            return
        }

        try ChildProcessTrap.assertTraps(
            test: #function,
            in: self,
            message: "Use init(sourceKeyID:destinationKeyID:failedAt:error:) to create a failed outcome."
        )
    }

    func test_notRecordedCompletionWithoutFailedOutcomeTraps() throws {
        if ChildProcessTrap.isRunningInTrapChildProcess {
            _ = PersistentKeyMigrationReport(
                outcomes: [.init(sourceKeyID: "a", status: .copied)],
                completion: .notRecorded
            )
            return
        }

        try ChildProcessTrap.assertTraps(
            test: #function,
            in: self,
            message: "A report whose completion was not recorded must have a failed outcome."
        )
    }

    func test_recordedCompletionWithFailedOutcomeTraps() throws {
        if ChildProcessTrap.isRunningInTrapChildProcess {
            _ = PersistentKeyMigrationReport(
                outcomes: [
                    .init(sourceKeyID: "a", failedAt: .write, error: PersistentKeyMigrationError.destinationChanged)
                ],
                completion: .recorded
            )
            return
        }

        try ChildProcessTrap.assertTraps(
            test: #function,
            in: self,
            message: "A report whose completion was recorded cannot have a failed outcome."
        )
    }

    #endif
}
