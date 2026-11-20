//
//  MigrationBackendCoverageTests.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 9/15/26.
//

import Combine
import Foundation
import XCTest

@testable import PersistentKeyValueKit

final class MigrationBackendCoverageTests: XCTestCase {
    private let intKey = PersistentKey("coverage.int", defaultValue: 0)
    private let optionalKey = PersistentKey<Int?>("coverage.optional", defaultValue: nil)

    // MARK: Tests

    func test_memoryDictionaryNormalization_dropsOptionalValues() throws {
        let store = InMemoryPersistentKeyValueStore()
        let key = PersistentKey<[String: Int?]>("coverage.dictionary", defaultValue: [:])

        store.set(key, to: ["kept": 1, "dropped": nil])

        XCTAssertEqual(store.get(key), ["kept": 1])

        let destination = InMemoryPersistentKeyValueStore()
        let write = try destination.prepareMigrationWrite(["kept": 2, "dropped": nil], for: key)

        _ = try destination.commitMigrationWrite(write, replacing: nil)

        XCTAssertEqual(destination.get(key), ["kept": 2])
    }

    func test_memoryObserverRefill_failsRemovalVerification() throws {
        let source = InMemoryPersistentKeyValueStore()
        let destination = InMemoryPersistentKeyValueStore()

        source.set(intKey, to: 1)
        let observer = CallbackObserver {
            source.set(self.intKey, to: 99)
        }

        source.register(observer: observer, for: intKey, with: nil, and: #selector(CallbackObserver.observeValue))

        defer {
            source.deregister(observer, for: intKey, context: nil)
        }

        let report = try source.move(intKey, to: destination, onConflict: .overwriteDestination, tracking: .untracked)

        guard case .failed(_) = report.outcomes[0].status, let error = report.outcomes[0].error else {
            return XCTFail("Expected a failed outcome with an error, got \(report.outcomes[0])")
        }

        XCTAssertEqual(error as? PersistentKeyMigrationError, .removalVerificationFailed)
        XCTAssertEqual(source.get(intKey), 99)
    }

    func test_memoryObserverReplacement_failsCommitVerification() throws {
        let source = InMemoryPersistentKeyValueStore()
        let destination = InMemoryPersistentKeyValueStore()

        source.set(intKey, to: 1)
        let observer = CallbackObserver {
            destination.set(self.intKey, to: 99)
        }

        destination.register(observer: observer, for: intKey, with: nil, and: #selector(CallbackObserver.observeValue))

        defer {
            destination.deregister(observer, for: intKey, context: nil)
        }

        let report = try source.copy(intKey, to: destination, onConflict: .overwriteDestination, tracking: .untracked)

        guard case .failed(_) = report.outcomes[0].status, let error = report.outcomes[0].error else {
            return XCTFail("Expected a failed outcome with an error, got \(report.outcomes[0])")
        }

        XCTAssertEqual(error as? PersistentKeyMigrationError, .writeVerificationFailed)
        XCTAssertEqual(destination.get(intKey), 99)
    }

    func test_memoryOptionalNormalization_preservesBoxedNil() throws {
        let store = InMemoryPersistentKeyValueStore()

        store.set(optionalKey, to: nil)
        let snapshot = try XCTUnwrap(store.migrationSnapshot(for: optionalKey.id))

        XCTAssertThrowsError(try store.migrationValue(for: intKey, in: snapshot))
        XCTAssertTrue(try store.migrationSnapshotIsCurrent(snapshot, for: optionalKey.id))
    }

    func test_memoryPrepare_preservesFoundationCollection() throws {
        let key = MutableArrayKey(id: "coverage.proxy")
        let store = InMemoryPersistentKeyValueStore()

        let write = try store.prepareMigrationWrite(NSMutableArray(array: [1]), for: key)
        _ = try store.commitMigrationWrite(write, replacing: nil)

        XCTAssertEqual(store.get(key), NSMutableArray(array: [1]))
    }

    func test_memoryPreparedNil_storesBoxedNilAndPreservesOtherKey() throws {
        let store = InMemoryPersistentKeyValueStore()

        store.set(intKey, to: 4)
        let write = try store.prepareMigrationWrite(nil, for: optionalKey)

        _ = try store.commitMigrationWrite(write, replacing: nil)

        XCTAssertNotNil(try store.migrationSnapshot(for: optionalKey.id))
        XCTAssertNil(store.get(optionalKey))
        XCTAssertEqual(store.get(intKey), 4)
    }

    func test_memoryStaleWriteAndRemoval_areRejected() throws {
        let store = InMemoryPersistentKeyValueStore()

        store.set(intKey, to: 1)
        let snapshot = try XCTUnwrap(store.migrationSnapshot(for: intKey.id))
        let write = try store.prepareMigrationWrite(2, for: intKey)

        store.set(intKey, to: 3)

        XCTAssertThrowsError(try store.commitMigrationWrite(write, replacing: snapshot))
        XCTAssertThrowsError(try store.removeMigrationValue(for: intKey.id, matching: snapshot))
    }

    func test_memoryWrongReplacementSnapshot_isRejected() throws {
        let store = InMemoryPersistentKeyValueStore()
        let otherKey = PersistentKey("coverage.other", defaultValue: 0)

        store.set(intKey, to: 1)
        store.set(otherKey, to: 2)
        let write = try store.prepareMigrationWrite(3, for: intKey)
        let other = try XCTUnwrap(store.migrationSnapshot(for: otherKey.id))

        XCTAssertThrowsError(try store.commitMigrationWrite(write, replacing: other))
    }

    func test_memoryWrongStoreAndKeyTokens_areRejected() throws {
        let first = InMemoryPersistentKeyValueStore()
        let second = InMemoryPersistentKeyValueStore()

        first.set(intKey, to: 1)
        let snapshot = try XCTUnwrap(first.migrationSnapshot(for: intKey.id))
        let write = try first.prepareMigrationWrite(2, for: intKey)

        XCTAssertThrowsError(try second.migrationValue(for: intKey, in: snapshot))
        XCTAssertThrowsError(try first.migrationSnapshotIsCurrent(snapshot, for: "other"))
        XCTAssertThrowsError(try second.commitMigrationWrite(write, replacing: nil))
        XCTAssertThrowsError(try first.removeMigrationValue(for: "other", matching: snapshot))
    }

    func test_standardFactory_validationAndEmptySuite() throws {
        if let identifier = Bundle.main.bundleIdentifier {
            XCTAssertEqual(
                try UserDefaults.migrationDomainName(for: .standard, applicationIdentifier: identifier),
                identifier
            )
        } else {
            XCTAssertThrowsError(try UserDefaults.migrationDomainName(for: .standard, applicationIdentifier: nil))
        }

        XCTAssertNoThrow(try UserDefaults.migrationDomainName(for: .standard, applicationIdentifier: "coverage.app"))
        XCTAssertThrowsError(try UserDefaults.migrationDomainName(for: .standard, applicationIdentifier: nil)) {
            XCTAssertEqual($0 as? PersistentKeyMigrationError, .missingApplicationIdentifier)
        }

        XCTAssertThrowsError(try UserDefaults.migrationDomainName(for: .standard, applicationIdentifier: "")) {
            XCTAssertEqual($0 as? PersistentKeyMigrationError, .missingApplicationIdentifier)
        }

        XCTAssertNil(UserDefaults.migratable(suiteName: ""))
        var called = false

        XCTAssertNil(
            UserDefaults.migratable(
                suiteName: "coverage",
                makeUserDefaults: { _ in
                    called = true

                    return nil
                }
            )
        )

        XCTAssertTrue(called)
    }

    @available(watchOS 9.0, *)
    func test_ubiquitousLegacyURLSnapshot_decodesAsURL() throws {
        let url = URL(string: "https://example.com/legacy")!
        let store = UbiquitousKeyValueMigrationBackend(
            store: LegacyURLUbiquitousStore(url: url),
            identity: .init(namespace: "legacy-url", identifier: UUID().uuidString)
        )
        let key = PersistentKey("key:\(#function)", defaultValue: URL(string: "https://example.com/default")!)

        let snapshot = try XCTUnwrap(try store.migrationSnapshot(for: key.id))

        XCTAssertEqual(snapshot.object as? URL, url)
        XCTAssertEqual(try store.migrationValue(for: key, in: snapshot), url)
    }

    @available(watchOS 9.0, *)
    func test_ubiquitousPublicConstructor_usesCanonicalIdentity() {
        let store = UbiquitousKeyValueMigrationBackend(StrictMigrationUbiquitousStore())

        XCTAssertEqual(store.migrationIdentity.namespace, "NSUbiquitousKeyValueStore")
        XCTAssertEqual(store.migrationIdentity.identifier, "default")
    }

    @available(watchOS 9.0, *)
    func test_ubiquitousRefusingRemoval_reportsFailureAndPreservesValue() throws {
        let raw = StrictMigrationUbiquitousStore()
        let store = UbiquitousKeyValueMigrationBackend(
            store: raw,
            identity: .init(namespace: "coverage", identifier: "remove")
        )
        let write = try store.prepareMigrationWrite(1, for: intKey)

        _ = try store.commitMigrationWrite(write, replacing: nil)
        let snapshot = try XCTUnwrap(store.migrationSnapshot(for: intKey.id))

        raw.rejectRemovals = true

        XCTAssertThrowsError(try store.removeMigrationValue(for: intKey.id, matching: snapshot)) {
            XCTAssertEqual($0 as? PersistentKeyMigrationError, .removalVerificationFailed)
        }

        XCTAssertNotNil(raw.storedValue(for: intKey.id))
    }

    @available(watchOS 9.0, *)
    func test_ubiquitousStaleAndWrongStoreTokens_areRejected() throws {
        let firstRaw = StrictMigrationUbiquitousStore()
        let secondRaw = StrictMigrationUbiquitousStore()
        let first = UbiquitousKeyValueMigrationBackend(
            store: firstRaw,
            identity: .init(namespace: "coverage", identifier: "first")
        )
        let second = UbiquitousKeyValueMigrationBackend(
            store: secondRaw,
            identity: .init(namespace: "coverage", identifier: "second")
        )
        let write = try first.prepareMigrationWrite(1, for: intKey)

        firstRaw.set(Int64(7), forKey: intKey.id)
        let snapshot = try XCTUnwrap(first.migrationSnapshot(for: intKey.id))

        firstRaw.set(Int64(8), forKey: intKey.id)

        XCTAssertThrowsError(try first.commitMigrationWrite(write, replacing: snapshot)) {
            XCTAssertEqual($0 as? PersistentKeyMigrationError, .destinationChanged)
        }

        XCTAssertThrowsError(try second.commitMigrationWrite(write, replacing: nil)) {
            XCTAssertEqual($0 as? PersistentKeyMigrationError, .internalInconsistency)
        }

        XCTAssertThrowsError(try second.migrationValue(for: intKey, in: snapshot)) {
            XCTAssertEqual($0 as? PersistentKeyMigrationError, .internalInconsistency)
        }

        XCTAssertThrowsError(try first.removeMigrationValue(for: intKey.id, matching: snapshot)) {
            XCTAssertEqual($0 as? PersistentKeyMigrationError, .sourceChanged)
        }
    }

    @available(watchOS 9.0, *)
    func test_ubiquitous_wrongTokensAndNilRemoval() throws {
        let raw = StrictMigrationUbiquitousStore()
        let store = UbiquitousKeyValueMigrationBackend(
            store: raw,
            identity: .init(namespace: "coverage", identifier: UUID().uuidString)
        )
        let write = try store.prepareMigrationWrite(1, for: intKey)

        _ = try store.commitMigrationWrite(write, replacing: nil)
        let snapshot = try XCTUnwrap(store.migrationSnapshot(for: intKey.id))

        XCTAssertThrowsError(try store.migrationSnapshotIsCurrent(snapshot, for: "other"))
        XCTAssertThrowsError(try store.removeMigrationValue(for: "other", matching: snapshot))

        let nilWrite = try store.prepareMigrationWrite(nil, for: optionalKey)

        XCTAssertNil(try store.commitMigrationWrite(nilWrite, replacing: nil))
        XCTAssertNil(raw.storedValue(for: optionalKey.id))
    }

    func test_userDefaults_constructorsAndNilWrite() throws {
        let suite = stableSuiteName("MigrationBackendCoverageTests")
        let defaults = try XCTUnwrap(UserDefaults.migratable(suiteName: suite))
        let store = UserDefaultsMigrationBackend(userDefaults: defaults, domainName: suite)

        defer {
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        }

        XCTAssertEqual(store.domainName, suite)

        let write = try store.prepareMigrationWrite(3, for: intKey)

        _ = try store.commitMigrationWrite(write, replacing: nil)
        let removal = try store.prepareMigrationWrite(nil, for: optionalKey)

        _ = try store.commitMigrationWrite(removal, replacing: nil)

        XCTAssertNil(try store.migrationSnapshot(for: optionalKey.id))
    }

    func test_userDefaultsRefusingStore_reportsWriteAndRemovalFailures() throws {
        let name = stableSuiteName("MigrationBackendCoverageTests.refusing")
        let raw = RefusingDefaults(suiteName: name)!
        let store = UserDefaultsMigrationBackend(userDefaults: raw, domainName: name)

        defer {
            raw.removePersistentDomain(forName: name)
        }

        raw.set(1, forKey: intKey.id)
        let snapshot = try XCTUnwrap(store.migrationSnapshot(for: intKey.id))
        let write = try store.prepareMigrationWrite(2, for: intKey)

        raw.refuseWrites = true

        XCTAssertThrowsError(try store.commitMigrationWrite(write, replacing: snapshot)) {
            XCTAssertEqual($0 as? PersistentKeyMigrationError, .writeVerificationFailed)
        }

        raw.refuseRemovals = true

        XCTAssertThrowsError(try store.removeMigrationValue(for: intKey.id, matching: snapshot)) {
            XCTAssertEqual($0 as? PersistentKeyMigrationError, .removalVerificationFailed)
        }
    }

    func test_userDefaultsSnapshotAndWriteTokens_rejectWrongKeyOrStore() throws {
        let firstName = stableSuiteName("MigrationBackendCoverageTests.first")
        let secondName = stableSuiteName("MigrationBackendCoverageTests.second")
        let first = UserDefaultsMigrationBackend(
            userDefaults: try XCTUnwrap(UserDefaults.migratable(suiteName: firstName)),
            domainName: firstName
        )
        let second = UserDefaultsMigrationBackend(
            userDefaults: try XCTUnwrap(UserDefaults.migratable(suiteName: secondName)),
            domainName: secondName
        )

        defer {
            UserDefaults(suiteName: firstName)?.removePersistentDomain(forName: firstName)
            UserDefaults(suiteName: secondName)?.removePersistentDomain(forName: secondName)
        }

        first.userDefaults.set(1, forKey: intKey.id)
        let snapshot = try XCTUnwrap(first.migrationSnapshot(for: intKey.id))
        let write = try first.prepareMigrationWrite(2, for: intKey)

        XCTAssertThrowsError(try second.migrationValue(for: intKey, in: snapshot))
        XCTAssertThrowsError(try first.migrationSnapshotIsCurrent(snapshot, for: "other"))
        XCTAssertThrowsError(try second.commitMigrationWrite(write, replacing: nil))
        XCTAssertThrowsError(try first.removeMigrationValue(for: "other", matching: snapshot))
    }

    func test_userDefaults_staleSnapshotAndAbsentInsertion() throws {
        let name = stableSuiteName("MigrationBackendCoverageTests.stale")
        let store = UserDefaultsMigrationBackend(
            userDefaults: try XCTUnwrap(UserDefaults.migratable(suiteName: name)),
            domainName: name
        )

        defer {
            UserDefaults(suiteName: name)?.removePersistentDomain(forName: name)
        }

        let write = try store.prepareMigrationWrite(1, for: intKey)

        store.userDefaults.set(8, forKey: intKey.id)

        XCTAssertThrowsError(try store.commitMigrationWrite(write, replacing: nil))

        let snapshot = try XCTUnwrap(store.migrationSnapshot(for: intKey.id))

        store.userDefaults.set(9, forKey: intKey.id)

        XCTAssertThrowsError(try store.commitMigrationWrite(write, replacing: snapshot))
        XCTAssertThrowsError(try store.removeMigrationValue(for: intKey.id, matching: snapshot))
    }
}

private final class RefusingDefaults: UserDefaults {
    var refuseRemovals = false
    var refuseWrites = false

    override func removeObject(forKey defaultName: String) {
        if !refuseRemovals {
            super.removeObject(forKey: defaultName)
        }
    }

    override func set(_ value: Any?, forKey defaultName: String) {
        if !refuseWrites {
            super.set(value, forKey: defaultName)
        }
    }
}

private final class CallbackObserver: NSObject {
    private let callback: () -> Void
    private var hasObserved = false
    init(_ callback: @escaping () -> Void) {
        self.callback = callback
    }

    @objc
    func observeValue() {
        guard !hasObserved else {
            return
        }

        hasObserved = true
        callback()
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

// MARK: - LegacyURLUbiquitousStore Definition

/// An iCloud store that returns a top-level `URL` object, as 1.x wrote, for every key.
@available(watchOS 9.0, *)
private final class LegacyURLUbiquitousStore: NSUbiquitousKeyValueStore {
    private let url: URL

    init(url: URL) {
        self.url = url

        super.init()
    }

    override func object(forKey key: String) -> Any? {
        url
    }
}
