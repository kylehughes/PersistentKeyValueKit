//
//  MigrationCoreTests.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 9/15/26.
//

import XCTest

@testable import PersistentKeyValueKit

final class MigrationCoreTests: XCTestCase {
    // MARK: Tests

    func test_absentOnlyBatch_recordsCompletion() throws {
        let (source, destination) = stores()
        let k = key()
        let report = try source.copy(
            k,
            to: destination,
            onConflict: .overwriteDestination,
            tracking: .once(id: #function, recordedIn: destination)
        )
        if case .recorded = report.completion {
        } else {
            XCTFail("expected recording")
        }

        XCTAssertTrue(destination.get(.isMigrationCompleted(id: #function)))
    }

    func test_absentSource_leavesDestination() throws {
        let (s, d) = stores()
        let k = key()

        d.set(k, to: "destination")
        let r = try s.copy(k, to: d, onConflict: .overwriteDestination, tracking: .untracked)

        status(r, .sourceAbsent)

        XCTAssertEqual(d.get(k), "destination")
    }

    func test_alreadyRecordedMarker_skips() throws {
        let (s, d) = stores()
        let k = key()
        let marker = PersistentKey<Bool>.isMigrationCompleted(id: #function)

        d.set(marker, to: true)
        let r = try s.copy(
            k,
            to: d,
            onConflict: .overwriteDestination,
            tracking: .once(id: #function, recordedIn: d)
        )
        if case .alreadyRecorded = r.completion {
        } else {
            XCTFail("did not skip")
        }
    }

    func test_batch_preservesOrder() throws {
        let (s, d) = stores()
        let a = key("a-\(#function)")
        let b = key("b-\(#function)")

        s.set(a, to: "a")
        s.set(b, to: "b")
        let r = try s.copy([a, b], to: d, onConflict: .overwriteDestination, tracking: .untracked)

        XCTAssertEqual(r.outcomes.map(\.sourceKeyID), [a.id, b.id])
        XCTAssertEqual(d.get(a), "a")
        XCTAssertEqual(d.get(b), "b")
    }

    func test_cleanupFailure_reportsFailure() throws {
        let s = MigrationFaultStore()
        let d = InMemoryPersistentKeyValueStore()
        let k = key()

        s.set(k, to: "source")
        s.failure = .remove
        let r = try s.move(k, to: d, onConflict: .overwriteDestination, tracking: .untracked)

        guard let outcome = r.outcomes.first, case .failed(.cleanup) = outcome.status else {
            return XCTFail("expected cleanup failure")
        }

        XCTAssertEqual(d.get(k), "source")
    }

    func test_completionCommitFailure_preservesTransferOutcome() throws {
        let source = InMemoryPersistentKeyValueStore()
        let destination = InMemoryPersistentKeyValueStore()
        let recorder = MigrationFaultStore()
        let k = key()

        source.set(k, to: "value")
        recorder.failure = .commit
        let report = try source.copy(
            k,
            to: destination,
            onConflict: .overwriteDestination,
            tracking: .once(id: #function, recordedIn: recorder)
        )

        XCTAssertEqual(destination.get(k), "value")
        if case .failed = report.completion {
        } else {
            XCTFail("expected completion failure")
        }

        XCTAssertTrue(report.hasFailures)
    }

    func test_completionIDs_areInjectiveForUnicodeAndPunctuation() {
        let a = PersistentKey<Bool>.isMigrationCompleted(id: "é/one?\n")
        let b = PersistentKey<Bool>.isMigrationCompleted(id: "é/one?\r")

        XCTAssertNotEqual(a.id, b.id)
        XCTAssertNotEqual(
            PersistentKey<Bool>.isMigrationCompleted(id: "Migration").id,
            PersistentKey<Bool>.isMigrationCompleted(id: "migration").id
        )
    }

    func test_completionMarkerIdentifier_containsNoDots() {
        let marker = PersistentKey<Bool>.isMigrationCompleted(id: "app-group.v1")

        XCTAssertTrue(marker.id.hasPrefix("PersistentKeyValueKit_MigrationCompleted_"))
        XCTAssertFalse(marker.id.contains("."))
        XCTAssertEqual(marker.id.utf16.count, 84)
    }

    func test_completionMarker_isObservableInUserDefaults() throws {
        let suiteName = stableSuiteName("MigrationCoreTests.observable")
        let defaults = try XCTUnwrap(UserDefaults.migratable(suiteName: suiteName))
        let marker = PersistentKey<Bool>.isMigrationCompleted(id: #function)
        let observer = MarkerObserver()

        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        defaults.register(observer: observer, for: marker, with: nil, and: #selector(MarkerObserver.observeValue))

        defer {
            defaults.deregister(observer, for: marker, context: nil)
        }

        let report = try InMemoryPersistentKeyValueStore().copy(
            items: [],
            to: defaults,
            onConflict: .overwriteDestination,
            tracking: .once(id: #function)
        )

        XCTAssertEqual(report.completion, .recorded)
        XCTAssertTrue(defaults.get(marker))
        XCTAssertEqual(observer.count, 1)
    }

    func test_completionMarker_treatsCanonicallyEquivalentIDsAsOneMigration() throws {
        let (s, d) = stores()
        let k = key()
        let composed = "caf\u{E9}"
        let decomposed = "cafe\u{301}"

        XCTAssertFalse(composed.utf8.elementsEqual(decomposed.utf8))
        XCTAssertEqual(
            PersistentKey<Bool>.isMigrationCompleted(id: composed).id,
            PersistentKey<Bool>.isMigrationCompleted(id: decomposed).id
        )

        s.set(k, to: "first")
        let first = try s.copy(k, to: d, onConflict: .overwriteDestination, tracking: .once(id: composed))

        XCTAssertEqual(first.completion, .recorded)

        d.set(k, to: "edited")
        let second = try s.copy(k, to: d, onConflict: .overwriteDestination, tracking: .once(id: decomposed))

        XCTAssertEqual(second.completion, .alreadyRecorded)
        XCTAssertEqual(d.get(k), "edited")
    }

    func test_longCompletionID_isRecordedInUbiquitousStore() throws {
        let source = InMemoryPersistentKeyValueStore()
        let destination = StrictMigrationUbiquitousStore()
        let k = key()
        let id = String(repeating: "long-migration-identifier/", count: 20)

        source.set(k, to: "value")

        let report = try source.copy(
            k,
            to: destination,
            onConflict: .overwriteDestination,
            tracking: .once(id: id, recordedIn: destination)
        )

        XCTAssertFalse(report.hasFailures)
        guard case .recorded = report.completion else {
            return XCTFail("expected recorded completion, got \(report.completion)")
        }
        XCTAssertLessThanOrEqual(PersistentKey<Bool>.isMigrationCompleted(id: id).id.utf16.count, 128)
        XCTAssertTrue(destination.get(.isMigrationCompleted(id: id)))
    }

    func test_completionMarker_isWrittenAfterMoveCleanup() throws {
        let source = InMemoryPersistentKeyValueStore()
        let destination = MigrationFaultStore()
        let k = key()

        source.set(k, to: "value")
        var markerObserved = false

        destination.commitHook = { keyID in
            if keyID.hasPrefix("PersistentKeyValueKit_MigrationCompleted_") {
                markerObserved =
                    (try? source.migrationSnapshot(for: k.id)) == nil && destination.get(k) == "value"
            }
        }

        let report = try source.move(
            k,
            to: destination,
            onConflict: .overwriteDestination,
            tracking: .once(id: #function, recordedIn: destination)
        )

        XCTAssertFalse(report.hasFailures)
        XCTAssertTrue(markerObserved)
    }

    func test_completionMarkerReset_allowsRerun() throws {
        let (s, d) = stores()
        let k = key()

        s.set(k, to: "one")
        _ = try s.copy(
            k,
            to: d,
            onConflict: .overwriteDestination,
            tracking: .once(id: #function, recordedIn: d)
        )
        d.remove(.isMigrationCompleted(id: #function))
        s.set(k, to: "two")
        let report = try s.copy(
            k,
            to: d,
            onConflict: .overwriteDestination,
            tracking: .once(id: #function, recordedIn: d)
        )
        if case .recorded = report.completion {
        } else {
            XCTFail("did not rerun")
        }

        XCTAssertEqual(d.get(k), "two")
    }

    func test_completionSnapshotFailure_precedesTransfer() throws {
        let source = InMemoryPersistentKeyValueStore()
        let destination = InMemoryPersistentKeyValueStore()
        let recorder = MigrationFaultStore()
        let k = key()

        source.set(k, to: "value")
        recorder.failure = .snapshot

        XCTAssertThrowsError(
            try source.copy(
                k,
                to: destination,
                onConflict: .overwriteDestination,
                tracking: .once(id: #function, recordedIn: recorder)
            )
        )

        XCTAssertEqual(destination.get(k), "default")
    }

    func test_conflictOnlyBatch_recordsAndPreservesDestination() throws {
        let (source, destination) = stores()
        let k = key()

        source.set(k, to: "source")
        destination.set(k, to: "destination")
        let report = try source.copy(
            k,
            to: destination,
            onConflict: .keepDestination,
            tracking: .once(id: #function, recordedIn: destination)
        )
        if case .recorded = report.completion {
        } else {
            XCTFail("expected recording")
        }

        XCTAssertEqual(source.get(k), "source")
        XCTAssertEqual(destination.get(k), "destination")
    }

    func test_copy_keepDestination() throws {
        let (s, d) = stores()
        let k = key()

        s.set(k, to: "source")
        d.set(k, to: "destination")
        let r = try s.copy(k, to: d, onConflict: .keepDestination, tracking: .untracked)

        status(r, .keptDestination)

        XCTAssertEqual(d.get(k), "destination")
    }

    func test_copy_overwriteDestination() throws {
        let (s, d) = stores()
        let k = key()

        s.set(k, to: "source")
        d.set(k, to: "destination")
        let r = try s.copy(k, to: d, onConflict: .overwriteDestination, tracking: .untracked)

        status(r, .copied)

        XCTAssertEqual(d.get(k), "source")
    }

    func test_decodeFailure_reportsDecodeStage() throws {
        let s = MigrationFaultStore()
        let d = InMemoryPersistentKeyValueStore()
        let k = key()

        s.set(k, to: "value")
        s.base.set(PersistentKey<Int>(k.id, defaultValue: 0), to: 1)
        let report = try s.copy(k, to: d, onConflict: .overwriteDestination, tracking: .untracked)

        guard case .failed(.decode) = report.outcomes[0].status else {
            return XCTFail("expected decode failure")
        }
    }

    func test_disabledDebugKey_doesNotTransfer() throws {
        let (s, d) = stores()
        let k = PersistentDebugKey<String>(
            #function,
            debugDefaultValue: "debug",
            releaseDefaultValue: "release"
        )
        s.set(k, to: "value")
        let r = try s.copy(k, to: d, onConflict: .overwriteDestination, tracking: .untracked)

        #if DEBUG
            status(r, .copied)
        #else
            status(r, .keyDisabled)
        #endif
    }

    func test_duplicateIdentifiers_areRejected() throws {
        let (s, d) = stores()
        let k = key()

        XCTAssertThrowsError(try s.copy([k, k], to: d, onConflict: .keepDestination, tracking: .untracked))
    }

    func test_emptyIdentifier_isRejected() throws {
        let (s, d) = stores()

        XCTAssertThrowsError(
            try s.copy(
                key(),
                to: d,
                onConflict: .keepDestination,
                tracking: .once(id: "", recordedIn: d)
            )
        )
    }

    func test_explicitDefaultValue_migrates() throws {
        let (s, d) = stores()
        let k = key()

        s.set(k, to: k.defaultValue)
        let r = try s.copy(k, to: d, onConflict: .overwriteDestination, tracking: .untracked)

        status(r, .copied)

        XCTAssertEqual(d.get(k), k.defaultValue)
    }

    func test_falseCompletionMarker_rerunsMigration() throws {
        let (source, destination) = stores()
        let k = key()

        source.set(k, to: "one")
        destination.set(.isMigrationCompleted(id: #function), to: false)
        let report = try source.copy(
            k,
            to: destination,
            onConflict: .overwriteDestination,
            tracking: .once(id: #function, recordedIn: destination)
        )
        if case .recorded = report.completion {
        } else {
            XCTFail("expected recording")
        }

        XCTAssertEqual(destination.get(k), "one")
    }

    func test_heterogeneousBatch_transfersDifferentValueTypes() throws {
        let (s, d) = stores()
        let number = PersistentKey<Int>("number-\(#function)", defaultValue: 0)
        let text = PersistentKey<String>("text-\(#function)", defaultValue: "")

        s.set(number, to: 42)
        s.set(text, to: "answer")
        let report = try s.copy([number, text], to: d, onConflict: .overwriteDestination, tracking: .untracked)

        XCTAssertEqual(report.outcomes.count, 2)
        XCTAssertEqual(d.get(number), 42)
        XCTAssertEqual(d.get(text), "answer")
    }

    func test_invalidIdentity_isRejected() throws {
        let s = InMemoryPersistentKeyValueStore()
        let d = MigrationFaultStore(identifier: "")

        XCTAssertThrowsError(try s.copy(key(), to: d, onConflict: .keepDestination, tracking: .untracked))
    }

    func test_malformedCompletionRecord_precedesTransfer() throws {
        let source = InMemoryPersistentKeyValueStore()
        let destination = InMemoryPersistentKeyValueStore()
        let recorder = MigrationFaultStore()
        let k = key()

        source.set(k, to: "value")
        recorder.base.set(.isMigrationCompleted(id: #function), to: false)
        recorder.malformedCompletionRecord = true

        XCTAssertThrowsError(
            try source.copy(
                k,
                to: destination,
                onConflict: .overwriteDestination,
                tracking: .once(id: #function, recordedIn: recorder)
            )
        ) { error in
            XCTAssertEqual(error as? PersistentKeyMigrationError, .invalidCompletionRecord)
        }

        XCTAssertEqual(destination.get(k), "default")
    }

    func test_move_keepBoth() throws {
        let (s, d) = stores()
        let k = key()

        s.set(k, to: "source")
        d.set(k, to: "destination")
        let r = try s.move(k, to: d, onConflict: .keepBoth, tracking: .untracked)

        status(r, .keptDestination)

        XCTAssertEqual(s.get(k), "source")
    }

    func test_move_keepDestinationAndRemoveSource() throws {
        let (s, d) = stores()
        let k = key()

        s.set(k, to: "source")
        d.set(k, to: "destination")
        let r = try s.move(k, to: d, onConflict: .keepDestinationAndRemoveSource, tracking: .untracked)

        status(r, .discardedSource)

        XCTAssertEqual(s.get(k), "default")
    }

    func test_move_overwriteDestination() throws {
        let (s, d) = stores()
        let k = key()

        s.set(k, to: "source")
        d.set(k, to: "destination")
        let r = try s.move(k, to: d, onConflict: .overwriteDestination, tracking: .untracked)

        status(r, .moved)

        XCTAssertEqual(s.get(k), "default")
        XCTAssertEqual(d.get(k), "source")
    }

    func test_optionalNilSource_isAbsent() throws {
        let (s, d) = stores()
        let k = PersistentKey<String?>(#function, defaultValue: nil)
        let r = try s.copy(k, to: d, onConflict: .overwriteDestination, tracking: .untracked)

        status(r, .sourceAbsent)

        XCTAssertNil(d.get(k))
    }

    func test_partialBatch_continues() throws {
        let s = InMemoryPersistentKeyValueStore()
        let d = MigrationFaultStore()
        let a = key("a-\(#function)")
        let b = key("b-\(#function)")

        s.set(a, to: "a")
        s.set(b, to: "b")
        d.failure = .commit
        d.failureKey = a.id
        let r = try s.copy([a, b], to: d, onConflict: .overwriteDestination, tracking: .untracked)

        XCTAssertEqual(r.outcomes.count, 2)

        guard case .failed(.write) = r.outcomes[0].status else {
            return XCTFail("expected first failure")
        }

        XCTAssertEqual(d.get(b), "b")
    }

    func test_prepareFailure_reportsPrepareStage() throws {
        let s = InMemoryPersistentKeyValueStore()
        let d = MigrationFaultStore()
        let k = key()

        s.set(k, to: "value")
        d.failure = .prepare
        let report = try s.copy(k, to: d, onConflict: .overwriteDestination, tracking: .untracked)

        guard case .failed(.prepare) = report.outcomes[0].status else {
            return XCTFail("expected prepare failure")
        }
    }

    func test_reentrantMigration_isRejectedAndRegistryReleases() throws {
        let s = InMemoryPersistentKeyValueStore()
        let d = MigrationFaultStore()
        let k = key()

        s.set(k, to: "value")
        var rejected = false

        d.hook = {
            do {
                _ = try s.copy(k, to: d, onConflict: .overwriteDestination, tracking: .untracked)
            } catch {
                rejected = true
            }
        }

        _ = try s.copy(k, to: d, onConflict: .overwriteDestination, tracking: .untracked)

        XCTAssertTrue(rejected)
        d.hook = nil

        XCTAssertNoThrow(try s.copy(k, to: d, onConflict: .overwriteDestination, tracking: .untracked))
    }

    func test_registry_releasesAfterFailure() throws {
        let s = InMemoryPersistentKeyValueStore()
        let d = MigrationFaultStore()
        let k = key()

        s.set(k, to: "value")
        d.failure = .commit
        _ = try s.copy(k, to: d, onConflict: .overwriteDestination, tracking: .untracked)
        d.failure = nil
        let r = try s.copy(k, to: d, onConflict: .overwriteDestination, tracking: .untracked)

        XCTAssertFalse(r.hasFailures)
    }

    func test_reservedIdentifier_isRejected() throws {
        let (s, d) = stores()
        let k = PersistentKey<String>("PersistentKeyValueKit_MigrationCompleted_bad", defaultValue: "")

        XCTAssertThrowsError(try s.copy(k, to: d, onConflict: .keepDestination, tracking: .untracked))
    }

    func test_sameStore_isRejected() throws {
        let s = InMemoryPersistentKeyValueStore()

        XCTAssertThrowsError(try s.copy(key(), to: s, onConflict: .keepDestination, tracking: .untracked))
    }

    func test_snapshotFailure_reportsSnapshotStage() throws {
        let s = MigrationFaultStore()
        let d = InMemoryPersistentKeyValueStore()
        let k = key()

        s.set(k, to: "value")
        s.failure = .snapshot
        let report = try s.copy(k, to: d, onConflict: .overwriteDestination, tracking: .untracked)

        guard case .failed(.snapshot) = report.outcomes[0].status else {
            return XCTFail("expected snapshot failure")
        }
    }

    func test_sourceChangeDuringCommit_preservesSource() throws {
        let s = InMemoryPersistentKeyValueStore()
        let d = MigrationFaultStore()
        let k = key()

        s.set(k, to: "old")
        d.hook = {
            s.set(k, to: "new")
        }

        let report = try s.move(k, to: d, onConflict: .overwriteDestination, tracking: .untracked)

        guard case .failed(.cleanup) = report.outcomes[0].status else {
            return XCTFail("expected cleanup failure")
        }

        XCTAssertEqual(s.get(k), "new")
    }

    func test_trackedFailure_canRetryAndRecord() throws {
        let s = InMemoryPersistentKeyValueStore()
        let d = MigrationFaultStore()
        let k = key()

        s.set(k, to: "value")
        d.failure = .commit
        let first = try s.copy(
            k,
            to: d,
            onConflict: .overwriteDestination,
            tracking: .once(id: #function, recordedIn: d)
        )
        if case .notRecorded = first.completion {
        } else {
            XCTFail("unexpected completion")
        }

        d.failure = nil
        let second = try s.copy(
            k,
            to: d,
            onConflict: .overwriteDestination,
            tracking: .once(id: #function, recordedIn: d)
        )
        if case .recorded = second.completion {
        } else {
            XCTFail("retry did not record")
        }
    }

    func test_trackedMigration_recordsMarker() throws {
        let (s, d) = stores()
        let k = key()

        s.set(k, to: "one")
        let r = try s.copy(
            k,
            to: d,
            onConflict: .overwriteDestination,
            tracking: .once(id: #function, recordedIn: d)
        )
        if case .recorded = r.completion {
        } else {
            XCTFail("not recorded")
        }

        XCTAssertTrue(d.get(.isMigrationCompleted(id: #function)))
    }

    func test_trackedSecondRun_skips() throws {
        let (s, d) = stores()
        let k = key()

        s.set(k, to: "one")
        _ = try s.copy(
            k,
            to: d,
            onConflict: .overwriteDestination,
            tracking: .once(id: #function, recordedIn: d)
        )
        s.set(k, to: "two")
        let r = try s.copy(
            k,
            to: d,
            onConflict: .overwriteDestination,
            tracking: .once(id: #function, recordedIn: d)
        )
        if case .alreadyRecorded = r.completion {
        } else {
            XCTFail("did not skip")
        }

        XCTAssertEqual(d.get(k), "one")
    }

    func test_untrackedMigration_repeats() throws {
        let (s, d) = stores()
        let k = key()

        s.set(k, to: "one")
        _ = try s.copy(k, to: d, onConflict: .overwriteDestination, tracking: .untracked)
        s.set(k, to: "two")
        _ = try s.copy(k, to: d, onConflict: .overwriteDestination, tracking: .untracked)

        XCTAssertEqual(d.get(k), "two")
    }

    func test_writeFailure_retainsSource() throws {
        let s = InMemoryPersistentKeyValueStore()
        let d = MigrationFaultStore()
        let k = key()

        s.set(k, to: "source")
        d.failure = .commit
        let r = try s.copy(k, to: d, onConflict: .overwriteDestination, tracking: .untracked)

        XCTAssertTrue(r.hasFailures)
        XCTAssertEqual(s.get(k), "source")
    }

    // MARK: Private Instance Interface

    private func key(_ name: String = #function) -> PersistentKey<String> {
        .init(name, defaultValue: "default")
    }

    private func status(
        _ report: PersistentKeyMigrationReport,
        _ expected: PersistentKeyMigrationReport.Status,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let actual = report.outcomes.first?.status else {
            XCTFail("missing outcome", file: file, line: line)

            return
        }

        switch (actual, expected) {
        case (.copied, .copied), (.moved, .moved), (.keptDestination, .keptDestination),
            (.discardedSource, .discardedSource), (.sourceAbsent, .sourceAbsent),
            (.keyDisabled, .keyDisabled):
            break
        default:
            XCTFail("unexpected status", file: file, line: line)
        }
    }

    private func stores() -> (InMemoryPersistentKeyValueStore, InMemoryPersistentKeyValueStore) {
        (.init(), .init())
    }
}

// MARK: - Marker Observer Definition

private final class MarkerObserver: NSObject {
    private(set) var count = 0

    // MARK: Internal Instance Interface

    @objc
    func observeValue() {
        count += 1
    }

    override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey: Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        observeValue()
    }
}
