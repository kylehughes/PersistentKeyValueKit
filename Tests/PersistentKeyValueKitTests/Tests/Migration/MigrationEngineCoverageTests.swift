import Foundation
import XCTest

@testable import PersistentKeyValueKit

private final class ScriptedMigrationStore {
    let base = InMemoryPersistentKeyValueStore()
    let migrationIdentity: PersistentKeyValueMigrationStoreIdentity
    var current = true
    var commitReturnsNil = false
    var commitReturnsFalseBool = false

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

// MARK: - PersistentKeyValueStore Extension

extension ScriptedMigrationStore: PersistentKeyValueStore {
    var migrationEndpoint: PersistentKeyValueMigrationEndpoint {
        .init(backend: self)
    }

    func deregister<Key>(
        _ observer: NSObject,
        for key: Key,
        context: UnsafeMutableRawPointer?
    ) where Key: PersistentKeyProtocol {
        base.deregister(observer, for: key, context: context)
    }

    func get<Key>(_ key: Key) -> Key.Value where Key: PersistentKeyProtocol {
        base.get(key)
    }

    func register<Key>(
        observer: NSObject,
        for key: Key,
        with context: UnsafeMutableRawPointer?,
        and selector: Selector
    ) where Key: PersistentKeyProtocol {
        base.register(observer: observer, for: key, with: context, and: selector)
    }

    func remove<Key>(_ key: Key) where Key: PersistentKeyProtocol {
        base.remove(key)
    }

    func set<Key>(_ key: Key, to value: Key.Value) where Key: PersistentKeyProtocol {
        base.set(key, to: value)
    }
}

final class MigrationEngineCoverageTests: XCTestCase {
    // MARK: Tests

    func testCompletionCurrentAndDecodedFalseVerificationFailures() throws {
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
            completion: .once(id: #function + "1", recordedIn: recorder)
        )
        if case .failed = first.completion {
        } else {
            XCTFail()
        }

        recorder.current = true
        recorder.commitReturnsFalseBool = true
        let second = try source.copy(
            k,
            to: destination,
            onConflict: .overwriteDestination,
            completion: .once(id: #function + "2", recordedIn: recorder)
        )
        if case .failed = second.completion {
        } else {
            XCTFail()
        }
    }

    func testCompletionRecordVerificationFailures() throws {
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
            completion: .once(id: #function, recordedIn: recorder)
        )
        if case .failed = report.completion {
        } else {
            XCTFail()
        }

        XCTAssertTrue(report.hasFailures)
        XCTAssertEqual(destination.get(k), 1)
    }

    func testConflictDiscardDestinationChangedReportsExactError() throws {
        let source = ScriptedMigrationStore()
        let destination = ScriptedMigrationStore()
        let k = key()

        source.set(k, to: 1)
        destination.set(k, to: 2)
        destination.current = false
        let report = try source.move(k, to: destination, onConflict: .keepDestinationAndRemoveSource)

        guard let outcome = report.outcomes.first, case .failed(.cleanup, let error) = outcome.status
        else {
            return XCTFail()
        }

        XCTAssertEqual(error as? PersistentKeyMigrationError, .destinationChanged)
        XCTAssertEqual(source.get(k), 1)
    }

    func testConflictDiscardSourceChangedReportsCleanup() throws {
        let source = ScriptedMigrationStore()
        let destination = ScriptedMigrationStore()
        let k = key()

        source.set(k, to: 1)
        destination.set(k, to: 2)
        source.current = false
        let report = try source.move(k, to: destination, onConflict: .keepDestinationAndRemoveSource)

        guard
            case .failed(.cleanup, PersistentKeyMigrationError.sourceChanged) = report.outcomes[0].status
        else {
            return XCTFail()
        }

        XCTAssertEqual(source.get(k), 1)
    }

    func testCustomDisabledKeyIsSkipped() throws {
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

            @available(watchOS 9.0, *)
            func get(from: NSUbiquitousKeyValueStore) -> Int {
                0
            }

            @available(watchOS 9.0, *)
            func remove(from: NSUbiquitousKeyValueStore) {
            }

            @available(watchOS 9.0, *)
            func set(to: Int, in: NSUbiquitousKeyValueStore) {
            }
        }

        let source = ScriptedMigrationStore()
        let destination = ScriptedMigrationStore()
        let k = DisabledKey(id: #function)

        source.set(k, to: 1)
        let report = try source.copy(k, to: destination, onConflict: .overwriteDestination)

        guard case .keyDisabled = report.outcomes[0].status else {
            return XCTFail()
        }

        XCTAssertEqual(destination.get(k), 0)
    }

    func testDestinationVerificationFalsePreservesSource() throws {
        let source = ScriptedMigrationStore()
        let destination = ScriptedMigrationStore()
        let k = key()

        source.set(k, to: 1)
        destination.current = false
        let report = try source.copy(k, to: destination, onConflict: .overwriteDestination)

        guard
            case .failed(.write, PersistentKeyMigrationError.writeVerificationFailed) = report.outcomes[0]
                .status
        else {
            return XCTFail()
        }

        XCTAssertEqual(source.get(k), 1)
    }

    func testInvalidSourceAndDestinationIdentities() throws {
        let source = ScriptedMigrationStore(namespace: "", identifier: "x")
        let destination = ScriptedMigrationStore()

        XCTAssertThrowsError(try source.copy(key(), to: destination, onConflict: .overwriteDestination)) {
            XCTAssertEqual($0 as? PersistentKeyMigrationError, .invalidStoreIdentifier)
        }

        let invalidDestination = ScriptedMigrationStore(namespace: "x", identifier: "")

        XCTAssertThrowsError(
            try destination.copy(key(), to: invalidDestination, onConflict: .overwriteDestination)
        )

        XCTAssertThrowsError(
            try destination.copy(
                key(),
                to: ScriptedMigrationStore(namespace: "", identifier: "x"),
                onConflict: .overwriteDestination
            )
        )

        XCTAssertThrowsError(
            try destination.copy(
                key(),
                to: ScriptedMigrationStore(),
                onConflict: .overwriteDestination,
                completion: .once(
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
                completion: .once(
                    id: "x",
                    recordedIn: ScriptedMigrationStore(namespace: "x", identifier: "")
                )
            )
        )
    }

    func testNilCommittedSnapshotReportsVerificationFailure() throws {
        let source = ScriptedMigrationStore()
        let destination = ScriptedMigrationStore()
        let k = key()

        source.set(k, to: 1)
        destination.set(k, to: 2)
        destination.commitReturnsNil = true
        let report = try source.copy(k, to: destination, onConflict: .overwriteDestination)

        guard
            case .failed(.write, PersistentKeyMigrationError.writeVerificationFailed) = report.outcomes[0]
                .status
        else {
            return XCTFail()
        }
    }

    func testReportCompletenessFlags() {
        let failure = PersistentKeyMigrationReport(outcomes: [], completion: .notRecorded)

        XCTAssertFalse(failure.hasFailures)
        XCTAssertFalse(failure.isComplete)

        let failedOutcome = PersistentKeyMigrationReport(
            outcomes: [
                .init(
                    keyID: "x",
                    status: .failed(stage: .write, error: PersistentKeyMigrationError.writeVerificationFailed)
                )
            ],
            completion: .untracked
        )

        XCTAssertTrue(failedOutcome.hasFailures)
        XCTAssertFalse(failedOutcome.isComplete)

        let failedCompletion = PersistentKeyMigrationReport(
            outcomes: [],
            completion: .failed(PersistentKeyMigrationError.writeVerificationFailed)
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
