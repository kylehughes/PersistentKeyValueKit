//
//  MigrationEngineCoverageTests.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 9/15/26.
//

import Foundation
import XCTest

@testable import PersistentKeyValueKit

private final class ScriptedMigrationStore {
    let base = InMemoryPersistentKeyValueStore()
    let migrationIdentity: PersistentKeyValueMigrationStoreIdentity
    var commitReturnsFalseBool = false
    var commitReturnsNil = false
    var current = true

    init(
        namespace: String = "scripted",
        identifier: String = UUID().uuidString
    ) {
        migrationIdentity = .init(namespace: namespace, identifier: identifier)
    }
}

// MARK: - PersistentKeyValueMigrationBackend Extension

extension ScriptedMigrationStore: PersistentKeyValueMigrationBackend {
    typealias MigrationSnapshot = InMemoryPersistentKeyValueStore.MigrationSnapshot

    typealias MigrationWrite = InMemoryPersistentKeyValueStore.MigrationWrite

    func commitMigrationWrite(
        _ write: MigrationWrite,
        replacing snapshot: MigrationSnapshot?
    ) throws -> MigrationSnapshot? {
        if commitReturnsNil {
            return nil
        }

        let committed = try base.commitMigrationWrite(
            .init(identity: base.migrationIdentity, keyID: write.keyID, object: write.object),
            replacing: snapshot.map {
                .init(
                    identity: base.migrationIdentity,
                    keyID: $0.keyID,
                    revision: $0.revision,
                    object: $0.object
                )
            }
        )
        if commitReturnsFalseBool, let committed {
            return .init(
                identity: migrationIdentity,
                keyID: committed.keyID,
                revision: committed.revision,
                object: false
            )
        }

        return committed.map {
            .init(
                identity: migrationIdentity,
                keyID: write.keyID,
                revision: $0.revision,
                object: $0.object
            )
        }
    }

    func migrationKeyIDExceedsLimit(_ keyID: String) -> Bool {
        false
    }

    func migrationKeyIdentity(_ keyID: String) -> PersistentKeyMigrationKeyIdentity {
        base.migrationKeyIdentity(keyID)
    }

    func migrationSnapshot(for keyID: String) throws -> MigrationSnapshot? {
        try base.migrationSnapshot(for: keyID).map {
            .init(identity: migrationIdentity, keyID: keyID, revision: $0.revision, object: $0.object)
        }
    }

    func migrationSnapshotIsCurrent(_ snapshot: MigrationSnapshot, for keyID: String) throws -> Bool {
        current
    }

    func migrationValue<Key>(
        for key: Key,
        in snapshot: MigrationSnapshot
    ) throws -> Key.Value where Key: PersistentKeyProtocol {
        try base.migrationValue(
            for: key,
            in: .init(
                identity: base.migrationIdentity,
                keyID: snapshot.keyID,
                revision: snapshot.revision,
                object: snapshot.object
            )
        )
    }

    func prepareMigrationWrite<Key>(
        _ value: Key.Value,
        for key: Key
    ) throws -> MigrationWrite where Key: PersistentKeyProtocol {
        let write = try base.prepareMigrationWrite(value, for: key)

        return .init(identity: migrationIdentity, keyID: key.id, object: write.object)
    }

    func removeMigrationValue(for keyID: String, matching snapshot: MigrationSnapshot) throws {
        try base.removeMigrationValue(
            for: keyID,
            matching: .init(
                identity: base.migrationIdentity,
                keyID: keyID,
                revision: snapshot.revision,
                object: snapshot.object
            )
        )
    }
}

// MARK: - ForwardingPersistentKeyValueStore Extension

extension ScriptedMigrationStore: ForwardingPersistentKeyValueStore {
    var migrationEndpoint: PersistentKeyValueMigrationEndpoint {
        .init(backend: self)
    }
}

final class MigrationEngineCoverageTests: XCTestCase {
    // MARK: Tests

    func test_completion_currentAndDecodedFalseVerificationFailures() throws {
        let source = ScriptedMigrationStore()
        let destination = ScriptedMigrationStore()
        let recorder = ScriptedMigrationStore()
        let k = key()

        source.set(k, to: 1)
        recorder.current = false
        let first = try source.copy(
            k,
            to: destination,
            onConflict: .overwriteDestination,
            tracking: .once(id: #function + "1", recordedIn: recorder)
        )
        XCTAssertEqual(first.completion, .failed)

        recorder.current = true
        recorder.commitReturnsFalseBool = true
        let second = try source.copy(
            k,
            to: destination,
            onConflict: .overwriteDestination,
            tracking: .once(id: #function + "2", recordedIn: recorder)
        )
        XCTAssertEqual(second.completion, .failed)
    }

    func test_completionRecord_verificationFailures() throws {
        let source = ScriptedMigrationStore()
        let destination = ScriptedMigrationStore()
        let recorder = ScriptedMigrationStore()
        let k = key()

        source.set(k, to: 1)
        recorder.commitReturnsNil = true
        let report = try source.copy(
            k,
            to: destination,
            onConflict: .overwriteDestination,
            tracking: .once(id: #function, recordedIn: recorder)
        )
        XCTAssertEqual(report.completion, .failed)

        XCTAssertTrue(report.hasFailures)
        XCTAssertEqual(destination.get(k), 1)
    }

    func test_conflictDiscardDestinationChanged_reportsExactError() throws {
        let source = ScriptedMigrationStore()
        let destination = ScriptedMigrationStore()
        let k = key()

        source.set(k, to: 1)
        destination.set(k, to: 2)
        destination.current = false
        let report = try source.move(
            k,
            to: destination,
            onConflict: .keepDestinationAndRemoveSource,
            tracking: .untracked
        )

        guard let outcome = report.outcomes.first, case .failed(.write) = outcome.status,
            let error = outcome.error
        else {
            return XCTFail("Expected a write failure with an error, got \(report.outcomes)")
        }

        XCTAssertEqual(error as? PersistentKeyMigrationError, .destinationChanged)
        XCTAssertEqual(source.get(k), 1)
    }

    func test_conflictDiscardSourceChanged_reportsCleanup() throws {
        let source = ScriptedMigrationStore()
        let destination = ScriptedMigrationStore()
        let k = key()

        source.set(k, to: 1)
        destination.set(k, to: 2)
        source.current = false
        let report = try source.move(
            k,
            to: destination,
            onConflict: .keepDestinationAndRemoveSource,
            tracking: .untracked
        )

        guard
            case .failed(.cleanup) = report.outcomes[0].status,
            report.outcomes[0].error as? PersistentKeyMigrationError == .sourceChanged
        else {
            return XCTFail("Expected a cleanup failure from a changed source, got \(report.outcomes[0])")
        }

        XCTAssertEqual(source.get(k), 1)
    }

    func test_customDisabledKey_isSkipped() throws {
        struct DisabledKey: PersistentKeyProtocol, Sendable {
            let id: String
            let defaultValue = 0
            let representation: any PersistentKeyValueRepresentation<Int> =
                PrimitivePersistentKeyValueRepresentation<Int>()
            var isMigrationEnabled: Bool {
                false
            }

            func get(from: UserDefaults) -> Int {
                0
            }

            func remove(from: UserDefaults) {
            }

            func set(to: Int, in: UserDefaults) {
            }

            func get(from: NSUbiquitousKeyValueStore) -> Int {
                0
            }

            func remove(from: NSUbiquitousKeyValueStore) {
            }

            func set(to: Int, in: NSUbiquitousKeyValueStore) {
            }
        }

        let source = ScriptedMigrationStore()
        let destination = ScriptedMigrationStore()
        let k = DisabledKey(id: #function)

        source.set(k, to: 1)
        let report = try source.copy(k, to: destination, onConflict: .overwriteDestination, tracking: .untracked)

        guard case .keyDisabled = report.outcomes[0].status else {
            return XCTFail("Expected a disabled key, got \(report.outcomes[0].status)")
        }

        XCTAssertEqual(destination.get(k), 0)
    }

    func test_destinationVerificationFalse_preservesSource() throws {
        let source = ScriptedMigrationStore()
        let destination = ScriptedMigrationStore()
        let k = key()

        source.set(k, to: 1)
        destination.current = false
        let report = try source.copy(k, to: destination, onConflict: .overwriteDestination, tracking: .untracked)

        guard
            case .failed(.write) = report.outcomes[0].status,
            report.outcomes[0].error as? PersistentKeyMigrationError == .writeVerificationFailed
        else {
            return XCTFail("Expected a write verification failure, got \(report.outcomes[0])")
        }

        XCTAssertEqual(source.get(k), 1)
    }

    func test_invalidSourceAndDestinationIdentities_throw() throws {
        let source = ScriptedMigrationStore(namespace: "", identifier: "x")
        let destination = ScriptedMigrationStore()

        XCTAssertThrowsError(
            try source.copy(key(), to: destination, onConflict: .overwriteDestination, tracking: .untracked)
        ) {
            XCTAssertEqual($0 as? PersistentKeyMigrationError, .internalInconsistency)
        }

        let invalidDestination = ScriptedMigrationStore(namespace: "x", identifier: "")

        XCTAssertThrowsError(
            try destination.copy(key(), to: invalidDestination, onConflict: .overwriteDestination, tracking: .untracked)
        )

        XCTAssertThrowsError(
            try destination.copy(
                key(),
                to: ScriptedMigrationStore(namespace: "", identifier: "x"),
                onConflict: .overwriteDestination,
                tracking: .untracked
            )
        )

        XCTAssertThrowsError(
            try destination.copy(
                key(),
                to: ScriptedMigrationStore(),
                onConflict: .overwriteDestination,
                tracking: .once(
                    id: "x",
                    recordedIn: ScriptedMigrationStore(namespace: "", identifier: "x")
                )
            )
        )

        XCTAssertThrowsError(
            try destination.copy(
                key(),
                to: ScriptedMigrationStore(),
                onConflict: .overwriteDestination,
                tracking: .once(
                    id: "x",
                    recordedIn: ScriptedMigrationStore(namespace: "x", identifier: "")
                )
            )
        )
    }

    func test_nilCommittedSnapshot_reportsVerificationFailure() throws {
        let source = ScriptedMigrationStore()
        let destination = ScriptedMigrationStore()
        let k = key()

        source.set(k, to: 1)
        destination.set(k, to: 2)
        destination.commitReturnsNil = true
        let report = try source.copy(k, to: destination, onConflict: .overwriteDestination, tracking: .untracked)

        guard
            case .failed(.write) = report.outcomes[0].status,
            report.outcomes[0].error as? PersistentKeyMigrationError == .writeVerificationFailed
        else {
            return XCTFail("Expected a write verification failure, got \(report.outcomes[0])")
        }
    }

    func test_report_completenessFlags() {
        let failedOutcome = PersistentKeyMigrationReport(
            outcomes: [
                .init(
                    sourceKeyID: "x",
                    failedAt: .write,
                    error: PersistentKeyMigrationError.writeVerificationFailed
                )
            ],
            completion: .untracked
        )

        XCTAssertTrue(failedOutcome.hasFailures)
        XCTAssertFalse(failedOutcome.isComplete)

        let failedCompletion = PersistentKeyMigrationReport(
            outcomes: [],
            completionError: PersistentKeyMigrationError.writeVerificationFailed
        )

        XCTAssertTrue(failedCompletion.hasFailures)
        XCTAssertFalse(failedCompletion.isComplete)

        let complete = PersistentKeyMigrationReport(outcomes: [], completion: .untracked)

        XCTAssertTrue(complete.isComplete)
    }

    // MARK: Private Instance Interface

    private func key(_ id: String = #function) -> PersistentKey<Int> {
        .init(id, defaultValue: 0)
    }
}
