//
//  MigrationBackendTests.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 9/15/26.
//

import Foundation
import XCTest

@testable import PersistentKeyValueKit

final class MigrationBackendTests: XCTestCase {
    // MARK: Tests

    func test_representations_codableAndURL() throws {
        let source = InMemoryPersistentKeyValueStore()
        let destination = InMemoryPersistentKeyValueStore()
        let valueKey = PersistentKey(
            "codable",
            defaultValue: CodableValue(name: "", count: 0),
            representation: CodablePersistentKeyValueRepresentation<CodableValue, JSONEncoder, JSONDecoder>()
        )
        source.set(valueKey, to: CodableValue(name: "x", count: 3))

        XCTAssertNoThrow(try source.copy(valueKey, to: destination, onConflict: .keepDestination, tracking: .untracked))
        XCTAssertEqual(destination.get(valueKey), CodableValue(name: "x", count: 3))

        let urlKey = PersistentKey("url", defaultValue: URL(string: "https://example.com")!)

        source.set(urlKey, to: URL(string: "https://swift.org")!)

        XCTAssertNoThrow(try source.copy(urlKey, to: destination, onConflict: .keepDestination, tracking: .untracked))
        XCTAssertEqual(destination.get(urlKey), URL(string: "https://swift.org")!)
    }

    func test_customProxyRepresentation_migratesWithoutAdditionalConformance() throws {
        let representation = ReferenceProxyPersistentKeyValueRepresentation<Int, Int>(
            serializing: {
                $0
            },
            deserializing: {
                $0
            }
        )
        let sourceName = stableSuiteName("MigrationBackendTests.unsupported.source")
        let destinationName = stableSuiteName("MigrationBackendTests.unsupported.destination")
        let sourceDefaults = UserDefaults(suiteName: sourceName)!
        let destinationDefaults = UserDefaults(suiteName: destinationName)!

        defer {
            sourceDefaults.removePersistentDomain(forName: sourceName)
            destinationDefaults.removePersistentDomain(forName: destinationName)
        }

        let source = UserDefaultsMigrationBackend(userDefaults: sourceDefaults, domainName: sourceName)
        let destination = UserDefaultsMigrationBackend(userDefaults: destinationDefaults, domainName: destinationName)
        let key = PersistentKey("unsupported", defaultValue: 1, representation: representation)

        sourceDefaults.set(2, forKey: key.id)
        let report = try source.copy(key, to: destination, onConflict: .keepDestination, tracking: .untracked)

        if case .copied = report.outcomes[0].status {
        } else {
            XCTFail("expected copy")
        }

        XCTAssertEqual(destinationDefaults.get(key), 2)
        XCTAssertEqual(sourceDefaults.get(key), 2)
    }

    func test_dateSnapshot_equality() throws {
        let defaults = try defaults()
        let key = PersistentKey("date", defaultValue: Date())

        defaults.userDefaults.set(Date(timeIntervalSince1970: 4), forKey: key.id)
        let snapshot = try XCTUnwrap(defaults.migrationSnapshot(for: key.id))

        XCTAssertTrue(try defaults.migrationSnapshotIsCurrent(snapshot, for: key.id))
    }

    func test_destinationInsertionBetweenAbsentSnapshotAndCommit_isRejected() throws {
        let destination = InMemoryPersistentKeyValueStore()
        let key = PersistentKey("insert", defaultValue: 0)
        let write = try destination.prepareMigrationWrite(1, for: key)

        destination.set(key, to: 2)

        XCTAssertThrowsError(try destination.commitMigrationWrite(write, replacing: nil))
        XCTAssertEqual(destination.get(key), 2)
    }

    func test_memory_batchAndAbsentSource() throws {
        let source = InMemoryPersistentKeyValueStore()
        let destination = InMemoryPersistentKeyValueStore()
        let a = PersistentKey("a", defaultValue: "")
        let b = PersistentKey("b", defaultValue: "")

        source.set(a, to: "one")
        let report = try source.copy([a, b], to: destination, onConflict: .keepDestination, tracking: .untracked)

        XCTAssertEqual(report.outcomes.map(\.sourceKeyID), ["a", "b"])
        XCTAssertEqual(destination.get(a), "one")
        XCTAssertEqual(report.outcomes[1].status, .sourceAbsent)
    }

    func test_memoryCollectionNormalization_unchanged() {
        let store = InMemoryPersistentKeyValueStore()
        let key = PersistentKey<[Int?]>("array", defaultValue: [])

        store.set(key, to: [1, nil, 2])

        XCTAssertEqual(store.get(key), [1, 2])
    }

    func test_memory_conflictPolicies() throws {
        let source = InMemoryPersistentKeyValueStore()
        let destination = InMemoryPersistentKeyValueStore()
        let key = PersistentKey("conflict", defaultValue: 0)

        source.set(key, to: 1)
        destination.set(key, to: 2)
        let keptCopy = try source.copy(key, to: destination, onConflict: .keepDestination, tracking: .untracked)

        XCTAssertEqual(keptCopy.outcomes[0].status, .keptDestination)

        let keptMove = try source.move(key, to: destination, onConflict: .keepBoth, tracking: .untracked)

        XCTAssertEqual(keptMove.outcomes[0].status, .keptDestination)

        let discardingMove = try source.move(
            key,
            to: destination,
            onConflict: .keepDestinationAndRemoveSource,
            tracking: .untracked
        )

        XCTAssertEqual(discardingMove.outcomes[0].status, .discardedSource)

        XCTAssertNil(try source.migrationSnapshot(for: key.id))
    }

    func test_memory_copyAndMove() throws {
        let source = InMemoryPersistentKeyValueStore()
        let destination = InMemoryPersistentKeyValueStore()
        let key = PersistentKey("copy", defaultValue: 0)

        source.set(key, to: 42)

        XCTAssertEqual(
            try source.copy(key, to: destination, onConflict: .keepDestination, tracking: .untracked).outcomes.count,
            1
        )
        XCTAssertEqual(destination.get(key), 42)
        XCTAssertEqual(
            try source.move(
                key,
                to: destination,
                onConflict: .overwriteDestination,
                tracking: .untracked
            ).outcomes.count,
            1
        )
        XCTAssertNil(try source.migrationSnapshot(for: key.id))
    }

    func test_memoryMutableReferenceSnapshot_comparesContents() throws {
        let store = InMemoryPersistentKeyValueStore()
        let key = MutableArrayKey(id: "key:\(#function)")
        let optionalID = "key:\(#function).optional"
        let opaqueID = "key:\(#function).opaque"
        let array = NSMutableArray(array: [1, 2])
        let optionalArray = NSMutableArray(array: [3])
        let opaqueArray = NSMutableArray(array: [NSNull()])

        store.set(key, to: array)
        store.set(Optional(optionalArray), forKey: optionalID)
        store.set(opaqueArray, forKey: opaqueID)

        let snapshot = try XCTUnwrap(store.migrationSnapshot(for: key.id))
        let optionalSnapshot = try XCTUnwrap(store.migrationSnapshot(for: optionalID))
        let opaqueSnapshot = try XCTUnwrap(store.migrationSnapshot(for: opaqueID))

        array.add(3)
        optionalArray.add(4)
        opaqueArray.add(NSNull())

        XCTAssertFalse(try store.migrationSnapshotIsCurrent(snapshot, for: key.id))
        XCTAssertFalse(try store.migrationSnapshotIsCurrent(optionalSnapshot, for: optionalID))
        // A reference that is not a property list cannot be copied, so it verifies by revision only.
        XCTAssertTrue(try store.migrationSnapshotIsCurrent(opaqueSnapshot, for: opaqueID))

        let write = try store.prepareMigrationWrite(NSMutableArray(array: [9]), for: key)

        XCTAssertThrowsError(try store.commitMigrationWrite(write, replacing: snapshot)) {
            XCTAssertEqual($0 as? PersistentKeyMigrationError, .destinationChanged)
        }

        XCTAssertThrowsError(try store.removeMigrationValue(for: key.id, matching: snapshot)) {
            XCTAssertEqual($0 as? PersistentKeyMigrationError, .sourceChanged)
        }

        XCTAssertEqual(store.get(key), NSMutableArray(array: [1, 2, 3]))

        let current = try XCTUnwrap(store.migrationSnapshot(for: key.id))

        XCTAssertTrue(try store.migrationSnapshotIsCurrent(current, for: key.id))
        XCTAssertNoThrow(try store.removeMigrationValue(for: key.id, matching: current))
    }

    func test_memoryMutableReferenceSnapshot_keepsExactContents() throws {
        let store = InMemoryPersistentKeyValueStore()
        let keyID = "key:\(#function)"
        let text = NSMutableString(string: "a")
        let data = NSMutableData(data: Data([1]))
        let nested = NSMutableDictionary(
            dictionary: ["decimal": NSDecimalNumber(string: "1.000000000000000001"), "text": text, "data": data]
        )

        store.set(NSMutableArray(array: [nested, 1]), forKey: keyID)

        // A serialized property list stores a decimal as a double, which cannot tell these two decimals apart.
        let mutations: [(String, () -> Void)] = [
            ("decimal", { nested["decimal"] = NSDecimalNumber(string: "1.000000000000000002") }),
            ("string", { text.append("b") }),
            ("data", { data.append(Data([2])) }),
            ("dictionary", { nested["added"] = true }),
        ]

        for (name, mutate) in mutations {
            let snapshot = try XCTUnwrap(store.migrationSnapshot(for: keyID), name)

            XCTAssertTrue(try store.migrationSnapshotIsCurrent(snapshot, for: keyID), name)
            mutate()
            XCTAssertFalse(try store.migrationSnapshotIsCurrent(snapshot, for: keyID), name)
        }
    }

    func test_mutablePayloadSnapshot_isFrozen() throws {
        let defaults = try defaults()
        let key = PersistentKey("data", defaultValue: Data())
        let mutable = NSMutableData(data: Data([1, 2]))

        defaults.userDefaults.set(mutable, forKey: key.id)
        let snapshot = try XCTUnwrap(defaults.migrationSnapshot(for: key.id))

        mutable.append(Data([3]))

        XCTAssertTrue(try defaults.migrationSnapshotIsCurrent(snapshot, for: key.id))
    }

    func test_nonEquatableValue_roundTripsInMemory() throws {
        let source = InMemoryPersistentKeyValueStore()
        let destination = InMemoryPersistentKeyValueStore()
        let key = PersistentKey(
            "nonEquatable",
            defaultValue: NonEquatableValue(value: ""),
            representation: CodablePersistentKeyValueRepresentation<NonEquatableValue, JSONEncoder, JSONDecoder>()
        )
        source.set(key, to: NonEquatableValue(value: "ok"))

        XCTAssertNoThrow(try source.copy(key, to: destination, onConflict: .keepDestination, tracking: .untracked))
        XCTAssertEqual(destination.get(key).value, "ok")
    }

    func test_optional_nilAndDefaultPresence() throws {
        let source = InMemoryPersistentKeyValueStore()
        let destination = InMemoryPersistentKeyValueStore()
        let optional = PersistentKey<Int?>("optional", defaultValue: 7)

        source.set(optional, to: nil)

        XCTAssertNotNil(try source.migrationSnapshot(for: optional.id))
        XCTAssertNoThrow(try source.copy(optional, to: destination, onConflict: .keepDestination, tracking: .untracked))
        XCTAssertNil(destination.get(optional))

        let absent = PersistentKey("absent", defaultValue: 8)

        XCTAssertNil(try source.migrationSnapshot(for: absent.id))

        let absentReport = try source.copy(absent, to: destination, onConflict: .keepDestination, tracking: .untracked)

        XCTAssertEqual(absentReport.outcomes[0].status, .sourceAbsent)
    }

    func test_sameUserDefaultsDomain_isRejected() throws {
        let name = stableSuiteName("MigrationBackendTests.alias")
        let defaults = UserDefaults(suiteName: name)!

        defer {
            defaults.removePersistentDomain(forName: name)
        }

        let a = UserDefaultsMigrationBackend(userDefaults: defaults, domainName: name)
        let b = UserDefaultsMigrationBackend(userDefaults: defaults, domainName: name)
        let key = PersistentKey("alias", defaultValue: 0)

        defaults.set(1, forKey: key.id)

        XCTAssertThrowsError(try a.move(key, to: b, onConflict: .keepBoth, tracking: .untracked))
        XCTAssertEqual(defaults.integer(forKey: key.id), 1)
    }

    func test_snapshotTokens_rejectWrongKeyAndStore() throws {
        let first = InMemoryPersistentKeyValueStore()
        let second = InMemoryPersistentKeyValueStore()
        let key = PersistentKey("token", defaultValue: 0)

        first.set(key, to: 1)
        let snapshot = try XCTUnwrap(first.migrationSnapshot(for: key.id))

        XCTAssertThrowsError(try second.migrationValue(for: key, in: snapshot))
        XCTAssertThrowsError(try first.migrationSnapshotIsCurrent(snapshot, for: "other"))
    }

    func test_ubiquitous_keyLengthBoundary() throws {
        let raw = StrictMigrationUbiquitousStore()
        let store = UbiquitousKeyValueMigrationBackend(
            store: raw,
            identity: .init(namespace: "test", identifier: UUID().uuidString)
        )

        XCTAssertFalse(store.migrationKeyIDExceedsLimit(String(repeating: "x", count: 128)))
        XCTAssertTrue(store.migrationKeyIDExceedsLimit(String(repeating: "x", count: 129)))
        XCTAssertFalse(store.migrationKeyIDExceedsLimit(String(repeating: "\u{1F600}", count: 64)))
        XCTAssertTrue(store.migrationKeyIDExceedsLimit(String(repeating: "\u{1F600}", count: 65)))
    }

    func test_ubiquitousQuota_isRejectedBeforeWrite() throws {
        let raw = StrictMigrationUbiquitousStore()
        let store = UbiquitousKeyValueMigrationBackend(
            store: raw,
            identity: .init(namespace: "test", identifier: UUID().uuidString)
        )
        let key = PersistentKey("cloud.large", defaultValue: Data())

        XCTAssertThrowsError(try store.prepareMigrationWrite(Data(repeating: 1, count: 1_048_577), for: key))
        XCTAssertNil(raw.storedValue(for: key.id))
    }

    func test_ubiquitousRejectedWrite_preservesDestination() throws {
        let raw = StrictMigrationUbiquitousStore()

        raw.set(Int64(8), forKey: "cloud.reject")
        let destination = UbiquitousKeyValueMigrationBackend(
            store: raw,
            identity: .init(namespace: "test", identifier: UUID().uuidString)
        )
        let source = InMemoryPersistentKeyValueStore()
        let key = PersistentKey("cloud.reject", defaultValue: 0)

        source.set(key, to: 1)
        raw.rejectWrites = true
        let report = try source.copy(key, to: destination, onConflict: .overwriteDestination, tracking: .untracked)

        guard case .failed = report.outcomes[0].status else {
            return XCTFail("Expected a failed outcome, got \(report.outcomes[0].status)")
        }

        XCTAssertEqual(raw.storedValue(for: key.id) as? Int64, 8)
    }

    func test_ubiquitousStore_doesNotSynchronize() throws {
        let raw = StrictMigrationUbiquitousStore()
        let store = UbiquitousKeyValueMigrationBackend(
            store: raw,
            identity: .init(namespace: "test", identifier: UUID().uuidString)
        )
        let key = PersistentKey("cloud", defaultValue: 0)

        raw.set(Int64(4), forKey: key.id)
        let destination = InMemoryPersistentKeyValueStore()

        XCTAssertNoThrow(try store.copy(key, to: destination, onConflict: .keepDestination, tracking: .untracked))
        XCTAssertEqual(raw.synchronizeCount, 0)
    }

    func test_userDefaultsCodableCodec_crossSuite() throws {
        let source = try defaults("codec.source")
        let destination = try defaults("codec.destination")
        let key = PersistentKey(
            "codec.cross",
            defaultValue: CodableValue(name: "", count: 0),
            representation: CodablePersistentKeyValueRepresentation<CodableValue, JSONEncoder, JSONDecoder>()
        )
        source.userDefaults.set(try JSONEncoder().encode(CodableValue(name: "encoded", count: 9)), forKey: key.id)

        XCTAssertNoThrow(try source.copy(key, to: destination, onConflict: .keepDestination, tracking: .untracked))

        let data = try XCTUnwrap(destination.userDefaults.data(forKey: key.id))

        XCTAssertEqual(
            try JSONDecoder().decode(CodableValue.self, from: data),
            CodableValue(name: "encoded", count: 9)
        )
    }

    func test_userDefaults_copyAndMoveBetweenSuites() throws {
        let sourceName = stableSuiteName("MigrationBackendTests.source")
        let destinationName = stableSuiteName("MigrationBackendTests.destination")
        let sourceDefaults = UserDefaults(suiteName: sourceName)!
        let destinationDefaults = UserDefaults(suiteName: destinationName)!

        defer {
            sourceDefaults.removePersistentDomain(forName: sourceName)
            destinationDefaults.removePersistentDomain(forName: destinationName)
        }

        let source = UserDefaultsMigrationBackend(userDefaults: sourceDefaults, domainName: sourceName)
        let destination = UserDefaultsMigrationBackend(userDefaults: destinationDefaults, domainName: destinationName)
        let key = PersistentKey("suite.key", defaultValue: "")

        sourceDefaults.set("hello", forKey: key.id)

        XCTAssertNoThrow(try source.copy(key, to: destination, onConflict: .keepDestination, tracking: .untracked))
        XCTAssertEqual(destinationDefaults.string(forKey: key.id), "hello")
        XCTAssertNoThrow(try source.move(key, to: destination, onConflict: .overwriteDestination, tracking: .untracked))
        XCTAssertNil(sourceDefaults.object(forKey: key.id))
    }

    func test_userDefaults_usesPersistedDomainOnly() throws {
        let name = stableSuiteName("MigrationBackendTests.persisted")
        let defaults = UserDefaults(suiteName: name)!

        defer {
            defaults.removePersistentDomain(forName: name)
        }

        defaults.register(defaults: ["registered": 1])
        defaults.set("persisted", forKey: "persisted")
        let store = UserDefaultsMigrationBackend(userDefaults: defaults, domainName: name)

        XCTAssertNil(try store.migrationSnapshot(for: "registered"))
        XCTAssertNotNil(try store.migrationSnapshot(for: "persisted"))
    }

    // MARK: Private Instance Interface

    private func defaults(
        _ suffix: String = "defaults",
        function: String = #function
    ) throws -> UserDefaultsMigrationBackend {
        let name = stableSuiteName("MigrationBackendTests.\(suffix)", function: function)
        let defaults = UserDefaults(suiteName: name)!

        addTeardownBlock {
            UserDefaults(suiteName: name)?.removePersistentDomain(forName: name)
        }

        return UserDefaultsMigrationBackend(userDefaults: defaults, domainName: name)
    }
}

// MARK: - Codable Value Definition

extension MigrationBackendTests {
    private struct CodableValue: Codable, Equatable, Sendable {
        let name: String
        let count: Int
    }
}

extension MigrationBackendTests {
    private struct NonEquatableValue: Codable, Sendable {
        let value: String
    }
}
