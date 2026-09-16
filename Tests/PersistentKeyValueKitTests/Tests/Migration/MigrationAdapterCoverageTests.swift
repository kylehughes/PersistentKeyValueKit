import Combine
import Foundation
import XCTest

@testable import PersistentKeyValueKit

final class MigrationAdapterCoverageTests: XCTestCase {
    private let intKey = PersistentKey("coverage.int", defaultValue: 0)
    private let optionalKey = PersistentKey<Int?>("coverage.optional", defaultValue: nil)

    // MARK: Tests

    func testMemoryDictionaryNormalizationDropsOptionalValues() throws {
        let store = InMemoryPersistentKeyValueStore()
        let key = PersistentKey<[String: Int?]>("coverage.dictionary", defaultValue: [:])

        store.set(key, to: ["kept": 1, "dropped": nil])

        XCTAssertEqual(store.get(key), ["kept": 1])

        let destination = InMemoryPersistentKeyValueStore()
        let write = try destination.prepareMigrationWrite(["kept": 2, "dropped": nil], for: key)

        _ = try destination.commitMigrationWrite(write, replacing: nil)

        XCTAssertEqual(destination.get(key), ["kept": 2])
    }

    func testMemoryObserverRefillFailsRemovalVerification() throws {
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

        let report = try source.move(intKey, to: destination, onConflict: .overwriteDestination)

        guard case .failed(_, let error) = report.outcomes[0].status else {
            return XCTFail()
        }

        XCTAssertEqual(error as? PersistentKeyMigrationError, .removalVerificationFailed)
        XCTAssertEqual(source.get(intKey), 99)
    }

    func testMemoryObserverReplacementFailsCommitVerification() throws {
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

        let report = try source.copy(intKey, to: destination, onConflict: .overwriteDestination)

        guard case .failed(_, let error) = report.outcomes[0].status else {
            return XCTFail()
        }

        XCTAssertEqual(error as? PersistentKeyMigrationError, .writeVerificationFailed)
        XCTAssertEqual(destination.get(intKey), 99)
    }

    func testMemoryOptionalNormalizationPreservesBoxedNil() throws {
        let store = InMemoryPersistentKeyValueStore()

        store.set(optionalKey, to: nil)
        let snapshot = try XCTUnwrap(store.migrationSnapshot(for: optionalKey.id))

        XCTAssertThrowsError(try store.migrationValue(for: intKey, in: snapshot))
        XCTAssertTrue(try store.migrationSnapshotIsCurrent(snapshot, for: optionalKey.id))
    }

    func testMemoryPrepareRejectsMismatchedNormalizedProxy() throws {
        let key = MutableArrayKey(id: "coverage.proxy")
        let store = InMemoryPersistentKeyValueStore()

        XCTAssertThrowsError(try store.prepareMigrationWrite(NSMutableArray(array: [1]), for: key)) { error in
            XCTAssertEqual(error as? PersistentKeyValueConversionError, .encodingFailed)
        }

        XCTAssertNil(try store.migrationSnapshot(for: key.id))
    }

    func testMemoryPreparedNilStoresBoxedNilAndPreservesOtherKey() throws {
        let store = InMemoryPersistentKeyValueStore()

        store.set(intKey, to: 4)
        let write = try store.prepareMigrationWrite(nil, for: optionalKey)

        _ = try store.commitMigrationWrite(write, replacing: nil)

        XCTAssertNotNil(try store.migrationSnapshot(for: optionalKey.id))
        XCTAssertNil(store.get(optionalKey))
        XCTAssertEqual(store.get(intKey), 4)
    }

    func testMemoryStaleWriteAndRemovalAreRejected() throws {
        let store = InMemoryPersistentKeyValueStore()

        store.set(intKey, to: 1)
        let snapshot = try XCTUnwrap(store.migrationSnapshot(for: intKey.id))
        let write = try store.prepareMigrationWrite(2, for: intKey)

        store.set(intKey, to: 3)

        XCTAssertThrowsError(try store.commitMigrationWrite(write, replacing: snapshot))
        XCTAssertThrowsError(try store.removeMigrationValue(for: intKey.id, matching: snapshot))
    }

    func testMemoryWrongReplacementSnapshotIsRejected() throws {
        let store = InMemoryPersistentKeyValueStore()
        let otherKey = PersistentKey("coverage.other", defaultValue: 0)

        store.set(intKey, to: 1)
        store.set(otherKey, to: 2)
        let write = try store.prepareMigrationWrite(3, for: intKey)
        let other = try XCTUnwrap(store.migrationSnapshot(for: otherKey.id))

        XCTAssertThrowsError(try store.commitMigrationWrite(write, replacing: other))
    }

    func testMemoryWrongStoreAndKeyTokensAreRejected() throws {
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

    func testStandardFactoryValidationAndEmptySuite() throws {
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
    func testUbiquitousPublicConstructorUsesCanonicalIdentity() {
        let store = UbiquitousKeyValueMigrationBackend(StrictMigrationUbiquitousStore())

        XCTAssertEqual(store.migrationIdentity.namespace, "NSUbiquitousKeyValueStore")
        XCTAssertEqual(store.migrationIdentity.identifier, "default")
    }

    @available(watchOS 9.0, *)
    func testUbiquitousRefusingRemovalReportsFailureAndPreservesValue() throws {
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
    func testUbiquitousStaleAndWrongStoreTokensAreRejected() throws {
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
            XCTAssertEqual($0 as? PersistentKeyMigrationError, .invalidSnapshot)
        }

        XCTAssertThrowsError(try second.migrationValue(for: intKey, in: snapshot)) {
            XCTAssertEqual($0 as? PersistentKeyMigrationError, .invalidSnapshot)
        }

        XCTAssertThrowsError(try first.removeMigrationValue(for: intKey.id, matching: snapshot)) {
            XCTAssertEqual($0 as? PersistentKeyMigrationError, .sourceChanged)
        }
    }

    @available(watchOS 9.0, *)
    func testUbiquitousWrongTokensAndNilRemoval() throws {
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

    func testUserDefaultsConstructorsAndNilWrite() throws {
        let suite = "MigrationAdapterCoverageTests.\(UUID().uuidString)"
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

    func testUserDefaultsRefusingStoreReportsWriteAndRemovalFailures() throws {
        let name = "MigrationAdapterCoverageTests.refusing.\(UUID().uuidString)"
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

    func testUserDefaultsSnapshotAndWriteTokensRejectWrongKeyOrStore() throws {
        let firstName = "MigrationAdapterCoverageTests.first.\(UUID().uuidString)"
        let secondName = "MigrationAdapterCoverageTests.second.\(UUID().uuidString)"
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

    func testUserDefaultsStaleSnapshotAndAbsentInsertion() throws {
        let name = "MigrationAdapterCoverageTests.stale.\(UUID().uuidString)"
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

private struct MutableArrayKey {
    let id: String
}

// MARK: - PersistentKeyProtocol Extension

extension MutableArrayKey: PersistentKeyProtocol {
    var defaultValue: NSMutableArray {
        NSMutableArray()
    }

    var representation: any PersistentKeyValueRepresentation<NSMutableArray> {
        ProxyPersistentKeyValueRepresentation<NSMutableArray, [Int]>(
            to: {
                $0 as? [Int] ?? []
            },
            from: {
                NSMutableArray(array: $0)
            }
        )
    }

    func get(from defaults: UserDefaults) -> NSMutableArray {
        representation.get(id, from: defaults) ?? defaultValue
    }

    @available(watchOS 9.0, *)
    func get(from store: NSUbiquitousKeyValueStore) -> NSMutableArray {
        representation.get(id, from: store) ?? defaultValue
    }

    func remove(from defaults: UserDefaults) {
        defaults.removeObject(forKey: id)
    }

    @available(watchOS 9.0, *)
    func remove(from store: NSUbiquitousKeyValueStore) {
        store.removeObject(forKey: id)
    }

    func set(to value: NSMutableArray, in defaults: UserDefaults) {
        representation.set(id, to: value, in: defaults)
    }

    @available(watchOS 9.0, *)
    func set(to value: NSMutableArray, in store: NSUbiquitousKeyValueStore) {
        representation.set(id, to: value, in: store)
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
