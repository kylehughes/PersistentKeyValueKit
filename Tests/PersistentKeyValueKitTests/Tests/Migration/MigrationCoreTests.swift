import XCTest

@testable import PersistentKeyValueKit

final class MigrationCoreTests: XCTestCase {
    private func key(_ name: String = #function) -> PersistentKey<String> {
        .init(name, defaultValue: "default")
    }
    private func stores() -> (InMemoryPersistentKeyValueStore, InMemoryPersistentKeyValueStore) {
        (.init(), .init())
    }
    private func status(
        _ report: PersistentKeyMigrationReport, _ expected: PersistentKeyMigrationReport.Status,
        file: StaticString = #filePath, line: UInt = #line
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
        default: XCTFail("unexpected status", file: file, line: line)
        }
    }

    func testCopyKeepDestination() throws {
        let (s, d) = stores()
        let k = key()
        s.set(k, to: "source")
        d.set(k, to: "destination")
        let r = try s.copy(k, to: d, onConflict: .keepDestination)
        status(r, .keptDestination)
        XCTAssertEqual(d.get(k), "destination")
    }
    func testCopyOverwriteDestination() throws {
        let (s, d) = stores()
        let k = key()
        s.set(k, to: "source")
        d.set(k, to: "destination")
        let r = try s.copy(k, to: d, onConflict: .overwriteDestination)
        status(r, .copied)
        XCTAssertEqual(d.get(k), "source")
    }
    func testMoveKeepBoth() throws {
        let (s, d) = stores()
        let k = key()
        s.set(k, to: "source")
        d.set(k, to: "destination")
        let r = try s.move(k, to: d, onConflict: .keepBoth)
        status(r, .keptDestination)
        XCTAssertEqual(s.get(k), "source")
    }
    func testMoveOverwriteDestination() throws {
        let (s, d) = stores()
        let k = key()
        s.set(k, to: "source")
        d.set(k, to: "destination")
        let r = try s.move(k, to: d, onConflict: .overwriteDestination)
        status(r, .moved)
        XCTAssertEqual(s.get(k), "default")
        XCTAssertEqual(d.get(k), "source")
    }
    func testMoveKeepDestinationAndRemoveSource() throws {
        let (s, d) = stores()
        let k = key()
        s.set(k, to: "source")
        d.set(k, to: "destination")
        let r = try s.move(k, to: d, onConflict: .keepDestinationAndRemoveSource)
        status(r, .discardedSource)
        XCTAssertEqual(s.get(k), "default")
    }
    func testAbsentSourceLeavesDestination() throws {
        let (s, d) = stores()
        let k = key()
        d.set(k, to: "destination")
        let r = try s.copy(k, to: d, onConflict: .overwriteDestination)
        status(r, .sourceAbsent)
        XCTAssertEqual(d.get(k), "destination")
    }
    func testExplicitDefaultValueMigrates() throws {
        let (s, d) = stores()
        let k = key()
        s.set(k, to: k.defaultValue)
        let r = try s.copy(k, to: d, onConflict: .overwriteDestination)
        status(r, .copied)
        XCTAssertEqual(d.get(k), k.defaultValue)
    }
    func testBatchPreservesOrder() throws {
        let (s, d) = stores()
        let a = key("a-\(#function)")
        let b = key("b-\(#function)")
        s.set(a, to: "a")
        s.set(b, to: "b")
        let r = try s.copy([a, b], to: d, onConflict: .overwriteDestination)
        XCTAssertEqual(r.outcomes.map(\.keyID), [a.id, b.id])
        XCTAssertEqual(d.get(a), "a")
        XCTAssertEqual(d.get(b), "b")
    }
    func testOptionalNilSourceIsAbsent() throws {
        let (s, d) = stores()
        let k = PersistentKey<String?>(#function, defaultValue: nil)
        let r = try s.copy(k, to: d, onConflict: .overwriteDestination)
        status(r, .sourceAbsent)
        XCTAssertNil(d.get(k))
    }
    func testUntrackedMigrationRepeats() throws {
        let (s, d) = stores()
        let k = key()
        s.set(k, to: "one")
        _ = try s.copy(k, to: d, onConflict: .overwriteDestination)
        s.set(k, to: "two")
        _ = try s.copy(k, to: d, onConflict: .overwriteDestination)
        XCTAssertEqual(d.get(k), "two")
    }
    func testTrackedMigrationRecordsMarker() throws {
        let (s, d) = stores()
        let k = key()
        s.set(k, to: "one")
        let r = try s.copy(
            k, to: d, onConflict: .overwriteDestination, completion: .once(id: #function, recordedIn: d))
        if case .recorded = r.completion {} else { XCTFail("not recorded") }
        XCTAssertTrue(d.get(.isMigrationCompleted(id: #function)))
    }
    func testTrackedSecondRunSkips() throws {
        let (s, d) = stores()
        let k = key()
        s.set(k, to: "one")
        _ = try s.copy(
            k, to: d, onConflict: .overwriteDestination, completion: .once(id: #function, recordedIn: d))
        s.set(k, to: "two")
        let r = try s.copy(
            k, to: d, onConflict: .overwriteDestination, completion: .once(id: #function, recordedIn: d))
        if case .alreadyRecorded = r.completion {} else { XCTFail("did not skip") }
        XCTAssertEqual(d.get(k), "one")
    }
    func testAlreadyRecordedMarkerSkips() throws {
        let (s, d) = stores()
        let k = key()
        let marker = PersistentKey<Bool>.isMigrationCompleted(id: #function)
        d.set(marker, to: true)
        let r = try s.copy(
            k, to: d, onConflict: .overwriteDestination, completion: .once(id: #function, recordedIn: d))
        if case .alreadyRecorded = r.completion {} else { XCTFail("did not skip") }
    }
    func testEmptyIdentifierRejected() throws {
        let (s, d) = stores()
        XCTAssertThrowsError(
            try s.copy(
                key(), to: d, onConflict: .keepDestination, completion: .once(id: "", recordedIn: d)))
    }
    func testDuplicateIdentifiersRejected() throws {
        let (s, d) = stores()
        let k = key()
        XCTAssertThrowsError(try s.copy([k, k], to: d, onConflict: .keepDestination))
    }
    func testReservedIdentifierRejected() throws {
        let (s, d) = stores()
        let k = PersistentKey<String>("PersistentKeyValueKit.MigrationCompleted.bad", defaultValue: "")
        XCTAssertThrowsError(try s.copy(k, to: d, onConflict: .keepDestination))
    }
    func testSameStoreRejected() throws {
        let s = InMemoryPersistentKeyValueStore()
        XCTAssertThrowsError(try s.copy(key(), to: s, onConflict: .keepDestination))
    }
    func testWriteFailureRetainsSource() throws {
        let s = InMemoryPersistentKeyValueStore()
        let d = MigrationFaultStore()
        let k = key()
        s.set(k, to: "source")
        d.failure = .commit
        let r = try s.copy(k, to: d, onConflict: .overwriteDestination)
        XCTAssertTrue(r.hasFailures)
        XCTAssertEqual(s.get(k), "source")
    }
    func testCleanupFailureReportsFailure() throws {
        let s = MigrationFaultStore()
        let d = InMemoryPersistentKeyValueStore()
        let k = key()
        s.set(k, to: "source")
        s.failure = .remove
        let r = try s.move(k, to: d, onConflict: .overwriteDestination)
        guard let outcome = r.outcomes.first, case .failed(.cleanup, _) = outcome.status else {
            return XCTFail("expected cleanup failure")
        }
        XCTAssertEqual(d.get(k), "source")
    }
    func testPartialBatchContinues() throws {
        let s = InMemoryPersistentKeyValueStore()
        let d = MigrationFaultStore()
        let a = key("a-\(#function)")
        let b = key("b-\(#function)")
        s.set(a, to: "a")
        s.set(b, to: "b")
        d.failure = .commit
        d.failureKey = a.id
        let r = try s.copy([a, b], to: d, onConflict: .overwriteDestination)
        XCTAssertEqual(r.outcomes.count, 2)
        guard case .failed(.write, _) = r.outcomes[0].status else {
            return XCTFail("expected first failure")
        }
        XCTAssertEqual(d.get(b), "b")
    }
    func testInvalidIdentityRejected() throws {
        let s = InMemoryPersistentKeyValueStore()
        let d = MigrationFaultStore(identifier: "")
        XCTAssertThrowsError(try s.copy(key(), to: d, onConflict: .keepDestination))
    }
    func testHeterogeneousBatchTransfersDifferentValueTypes() throws {
        let (s, d) = stores()
        let number = PersistentKey<Int>("number-\(#function)", defaultValue: 0)
        let text = PersistentKey<String>("text-\(#function)", defaultValue: "")
        s.set(number, to: 42)
        s.set(text, to: "answer")
        let report = try s.copy([number, text], to: d, onConflict: .overwriteDestination)
        XCTAssertEqual(report.outcomes.count, 2)
        XCTAssertEqual(d.get(number), 42)
        XCTAssertEqual(d.get(text), "answer")
    }
    func testDecodeFailureReportsDecodeStage() throws {
        let s = MigrationFaultStore()
        let d = InMemoryPersistentKeyValueStore()
        let k = key()
        s.set(k, to: "value")
        s.base.set(PersistentKey<Int>(k.id, defaultValue: 0), to: 1)
        let report = try s.copy(k, to: d, onConflict: .overwriteDestination)
        guard case .failed(.decode, _) = report.outcomes[0].status else {
            return XCTFail("expected decode failure")
        }
    }
    func testPrepareFailureReportsPrepareStage() throws {
        let s = InMemoryPersistentKeyValueStore()
        let d = MigrationFaultStore()
        let k = key()
        s.set(k, to: "value")
        d.failure = .prepare
        let report = try s.copy(k, to: d, onConflict: .overwriteDestination)
        guard case .failed(.prepare, _) = report.outcomes[0].status else {
            return XCTFail("expected prepare failure")
        }
    }
    func testSnapshotFailureReportsSnapshotStage() throws {
        let s = MigrationFaultStore()
        let d = InMemoryPersistentKeyValueStore()
        let k = key()
        s.set(k, to: "value")
        s.failure = .snapshot
        let report = try s.copy(k, to: d, onConflict: .overwriteDestination)
        guard case .failed(.snapshot, _) = report.outcomes[0].status else {
            return XCTFail("expected snapshot failure")
        }
    }
    func testTrackedFailureCanRetryAndRecord() throws {
        let s = InMemoryPersistentKeyValueStore()
        let d = MigrationFaultStore()
        let k = key()
        s.set(k, to: "value")
        d.failure = .commit
        let first = try s.copy(
            k, to: d, onConflict: .overwriteDestination, completion: .once(id: #function, recordedIn: d))
        if case .notRecorded = first.completion {} else { XCTFail("unexpected completion") }
        d.failure = nil
        let second = try s.copy(
            k, to: d, onConflict: .overwriteDestination, completion: .once(id: #function, recordedIn: d))
        if case .recorded = second.completion {} else { XCTFail("retry did not record") }
    }
    func testCompletionMarkerResetAllowsRerun() throws {
        let (s, d) = stores()
        let k = key()
        s.set(k, to: "one")
        _ = try s.copy(
            k, to: d, onConflict: .overwriteDestination, completion: .once(id: #function, recordedIn: d))
        d.remove(.isMigrationCompleted(id: #function))
        s.set(k, to: "two")
        let report = try s.copy(
            k, to: d, onConflict: .overwriteDestination, completion: .once(id: #function, recordedIn: d))
        if case .recorded = report.completion {} else { XCTFail("did not rerun") }
        XCTAssertEqual(d.get(k), "two")
    }
    func testSourceChangeDuringCommitPreservesSource() throws {
        let s = InMemoryPersistentKeyValueStore()
        let d = MigrationFaultStore()
        let k = key()
        s.set(k, to: "old")
        d.hook = { s.set(k, to: "new") }
        let report = try s.move(k, to: d, onConflict: .overwriteDestination)
        guard case .failed(.cleanup, _) = report.outcomes[0].status else {
            return XCTFail("expected cleanup failure")
        }
        XCTAssertEqual(s.get(k), "new")
    }
    func testReentrantMigrationIsRejectedAndRegistryReleases() throws {
        let s = InMemoryPersistentKeyValueStore()
        let d = MigrationFaultStore()
        let k = key()
        s.set(k, to: "value")
        var rejected = false
        d.hook = {
            do { _ = try s.copy(k, to: d, onConflict: .overwriteDestination) } catch { rejected = true }
        }
        _ = try s.copy(k, to: d, onConflict: .overwriteDestination)
        XCTAssertTrue(rejected)
        d.hook = nil
        XCTAssertNoThrow(try s.copy(k, to: d, onConflict: .overwriteDestination))
    }
    func testDisabledDebugKeyDoesNotTransfer() throws {
        let (s, d) = stores()
        let k = PersistentDebugKey<String>(
            #function, debugDefaultValue: "debug", releaseDefaultValue: "release")
        s.set(k, to: "value")
        let r = try s.copy(k, to: d, onConflict: .overwriteDestination)
        #if DEBUG
            status(r, .copied)
        #else
            status(r, .keyDisabled)
        #endif
    }
    func testRegistryReleasesAfterFailure() throws {
        let s = InMemoryPersistentKeyValueStore()
        let d = MigrationFaultStore()
        let k = key()
        s.set(k, to: "value")
        d.failure = .commit
        _ = try s.copy(k, to: d, onConflict: .overwriteDestination)
        d.failure = nil
        let r = try s.copy(k, to: d, onConflict: .overwriteDestination)
        XCTAssertFalse(r.hasFailures)
    }
    func testCompletionCommitFailurePreservesTransferOutcome() throws {
        let source = InMemoryPersistentKeyValueStore()
        let destination = InMemoryPersistentKeyValueStore()
        let recorder = MigrationFaultStore()
        let k = key()
        source.set(k, to: "value")
        recorder.failure = .commit
        let report = try source.copy(
            k, to: destination, onConflict: .overwriteDestination,
            completion: .once(id: #function, recordedIn: recorder))
        XCTAssertEqual(destination.get(k), "value")
        if case .failed = report.completion {} else { XCTFail("expected completion failure") }
        XCTAssertTrue(report.hasFailures)
    }
    func testCompletionSnapshotFailurePrecedesTransfer() throws {
        let source = InMemoryPersistentKeyValueStore()
        let destination = InMemoryPersistentKeyValueStore()
        let recorder = MigrationFaultStore()
        let k = key()
        source.set(k, to: "value")
        recorder.failure = .snapshot
        XCTAssertThrowsError(
            try source.copy(
                k, to: destination, onConflict: .overwriteDestination,
                completion: .once(id: #function, recordedIn: recorder)))
        XCTAssertEqual(destination.get(k), "default")
    }
    func testMalformedCompletionRecordPrecedesTransfer() throws {
        let source = InMemoryPersistentKeyValueStore()
        let destination = InMemoryPersistentKeyValueStore()
        let recorder = MigrationFaultStore()
        let k = key()
        source.set(k, to: "value")
        recorder.base.set(.isMigrationCompleted(id: #function), to: false)
        recorder.malformedCompletionRecord = true
        XCTAssertThrowsError(
            try source.copy(
                k, to: destination, onConflict: .overwriteDestination,
                completion: .once(id: #function, recordedIn: recorder))
        ) { error in XCTAssertEqual(error as? PersistentKeyMigrationError, .invalidCompletionRecord) }
        XCTAssertEqual(destination.get(k), "default")
    }
    func testFalseCompletionMarkerRerunsMigration() throws {
        let (source, destination) = stores()
        let k = key()
        source.set(k, to: "one")
        destination.set(.isMigrationCompleted(id: #function), to: false)
        let report = try source.copy(
            k, to: destination, onConflict: .overwriteDestination,
            completion: .once(id: #function, recordedIn: destination))
        if case .recorded = report.completion {} else { XCTFail("expected recording") }
        XCTAssertEqual(destination.get(k), "one")
    }
    func testCompletionIDsAreInjectiveForUnicodeAndPunctuation() {
        let a = PersistentKey<Bool>.isMigrationCompleted(id: "é/one?\n")
        let b = PersistentKey<Bool>.isMigrationCompleted(id: "é/one?\r")
        XCTAssertNotEqual(a.id, b.id)
    }
    func testAbsentOnlyBatchRecordsCompletion() throws {
        let (source, destination) = stores()
        let k = key()
        let report = try source.copy(
            k, to: destination, onConflict: .overwriteDestination,
            completion: .once(id: #function, recordedIn: destination))
        if case .recorded = report.completion {} else { XCTFail("expected recording") }
        XCTAssertTrue(destination.get(.isMigrationCompleted(id: #function)))
    }
    func testConflictOnlyBatchRecordsAndPreservesDestination() throws {
        let (source, destination) = stores()
        let k = key()
        source.set(k, to: "source")
        destination.set(k, to: "destination")
        let report = try source.copy(
            k, to: destination, onConflict: .keepDestination,
            completion: .once(id: #function, recordedIn: destination))
        if case .recorded = report.completion {} else { XCTFail("expected recording") }
        XCTAssertEqual(source.get(k), "source")
        XCTAssertEqual(destination.get(k), "destination")
    }

    func testCompletionMarkerIsWrittenAfterMoveCleanup() throws {
        let source = InMemoryPersistentKeyValueStore()
        let destination = MigrationFaultStore()
        let k = key()
        source.set(k, to: "value")
        var markerObserved = false
        destination.commitHook = { keyID in
            if keyID.hasPrefix("PersistentKeyValueKit.MigrationCompleted.") {
                markerObserved =
                    (try? source.migrationSnapshot(for: k.id)) == nil && destination.get(k) == "value"
            }
        }
        let report = try source.move(
            k, to: destination, onConflict: .overwriteDestination,
            completion: .once(id: #function, recordedIn: destination))
        XCTAssertFalse(report.hasFailures)
        XCTAssertTrue(markerObserved)
    }
}
