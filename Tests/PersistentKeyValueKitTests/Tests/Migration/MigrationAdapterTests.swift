import Foundation
import XCTest

@testable import PersistentKeyValueKit

final class MigrationAdapterTests: XCTestCase {
    // MARK: Tests

    @available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
    func testCodableAndURLRepresentations() throws {
        let source = InMemoryPersistentKeyValueStore()
        let destination = InMemoryPersistentKeyValueStore()
        let valueKey = PersistentKey(
            "codable",
            defaultValue: CodableValue(name: "", count: 0),
            representation: CodablePersistentKeyValueRepresentation<CodableValue, JSONEncoder, JSONDecoder>()
        )
        source.set(valueKey, to: CodableValue(name: "x", count: 3))

        XCTAssertNoThrow(try source.copy(valueKey, to: destination, onConflict: .keepDestination))
        XCTAssertEqual(destination.get(valueKey), CodableValue(name: "x", count: 3))

        let urlKey = PersistentKey("url", defaultValue: URL(string: "https://example.com")!)

        source.set(urlKey, to: URL(string: "https://swift.org")!)

        XCTAssertNoThrow(try source.copy(urlKey, to: destination, onConflict: .keepDestination))
        XCTAssertEqual(destination.get(urlKey), URL(string: "https://swift.org")!)
    }

    func testCustomProxyRepresentationMigratesWithoutAdditionalConformance() throws {
        let representation = ReferenceProxyPersistentKeyValueRepresentation<Int, Int>(
            serializing: {
                $0
            },
            deserializing: {
                $0
            }
        )
        let sourceName = "MigrationAdapterTests.unsupported.source.\(UUID().uuidString)"
        let destinationName = "MigrationAdapterTests.unsupported.destination.\(UUID().uuidString)"
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
        let report = try source.copy(key, to: destination, onConflict: .keepDestination)

        if case .copied = report.outcomes[0].status {
        } else {
            XCTFail("expected copy")
        }

        XCTAssertEqual(destinationDefaults.get(key), 2)
        XCTAssertEqual(sourceDefaults.get(key), 2)
    }

    func testDateSnapshotEquality() throws {
        let defaults = try defaults()
        let key = PersistentKey("date", defaultValue: Date())

        defaults.userDefaults.set(Date(timeIntervalSince1970: 4), forKey: key.id)
        let snapshot = try XCTUnwrap(defaults.migrationSnapshot(for: key.id))

        XCTAssertTrue(try defaults.migrationSnapshotIsCurrent(snapshot, for: key.id))
    }

    func testDestinationInsertionBetweenAbsentSnapshotAndCommitIsRejected() throws {
        let destination = InMemoryPersistentKeyValueStore()
        let key = PersistentKey("insert", defaultValue: 0)
        let write = try destination.prepareMigrationWrite(1, for: key)

        destination.set(key, to: 2)

        XCTAssertThrowsError(try destination.commitMigrationWrite(write, replacing: nil))
        XCTAssertEqual(destination.get(key), 2)
    }

    func testMemoryBatchAndAbsentSource() throws {
        let source = InMemoryPersistentKeyValueStore()
        let destination = InMemoryPersistentKeyValueStore()
        let a = PersistentKey("a", defaultValue: "")
        let b = PersistentKey("b", defaultValue: "")

        source.set(a, to: "one")
        let report = try source.copy([a, b], to: destination, onConflict: .keepDestination)

        XCTAssertEqual(report.outcomes.map(\.keyID), ["a", "b"])
        XCTAssertEqual(destination.get(a), "one")
        if case .sourceAbsent = report.outcomes[1].status {
        } else {
            XCTFail()
        }
    }

    func testMemoryCollectionNormalizationUnchanged() {
        let store = InMemoryPersistentKeyValueStore()
        let key = PersistentKey<[Int?]>("array", defaultValue: [])

        store.set(key, to: [1, nil, 2])

        XCTAssertEqual(store.get(key), [1, 2])
    }

    func testMemoryConflictPolicies() throws {
        let source = InMemoryPersistentKeyValueStore()
        let destination = InMemoryPersistentKeyValueStore()
        let key = PersistentKey("conflict", defaultValue: 0)

        source.set(key, to: 1)
        destination.set(key, to: 2)
        if case .keptDestination = try source.copy(key, to: destination, onConflict: .keepDestination).outcomes[0]
            .status
        {
        } else {
            XCTFail()
        }

        if case .keptDestination = try source.move(key, to: destination, onConflict: .keepBoth).outcomes[0].status {
        } else {
            XCTFail()
        }

        if case .discardedSource = try source.move(key, to: destination, onConflict: .keepDestinationAndRemoveSource)
            .outcomes[0].status
        {
        } else {
            XCTFail()
        }

        XCTAssertNil(try source.migrationSnapshot(for: key.id))
    }

    func testMemoryCopyAndMove() throws {
        let source = InMemoryPersistentKeyValueStore()
        let destination = InMemoryPersistentKeyValueStore()
        let key = PersistentKey("copy", defaultValue: 0)

        source.set(key, to: 42)

        XCTAssertEqual(try source.copy(key, to: destination, onConflict: .keepDestination).outcomes.count, 1)
        XCTAssertEqual(destination.get(key), 42)
        XCTAssertEqual(try source.move(key, to: destination, onConflict: .overwriteDestination).outcomes.count, 1)
        XCTAssertNil(try source.migrationSnapshot(for: key.id))
    }

    func testMutablePayloadSnapshotIsFrozen() throws {
        let defaults = try defaults()
        let key = PersistentKey("data", defaultValue: Data())
        let mutable = NSMutableData(data: Data([1, 2]))

        defaults.userDefaults.set(mutable, forKey: key.id)
        let snapshot = try XCTUnwrap(defaults.migrationSnapshot(for: key.id))

        mutable.append(Data([3]))

        XCTAssertTrue(try defaults.migrationSnapshotIsCurrent(snapshot, for: key.id))
    }

    @available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
    func testNonEquatableValueRoundTripsInMemory() throws {
        let source = InMemoryPersistentKeyValueStore()
        let destination = InMemoryPersistentKeyValueStore()
        let key = PersistentKey(
            "nonEquatable",
            defaultValue: NonEquatableValue(value: ""),
            representation: CodablePersistentKeyValueRepresentation<NonEquatableValue, JSONEncoder, JSONDecoder>()
        )
        source.set(key, to: NonEquatableValue(value: "ok"))

        XCTAssertNoThrow(try source.copy(key, to: destination, onConflict: .keepDestination))
        XCTAssertEqual(destination.get(key).value, "ok")
    }

    func testOptionalNilAndDefaultPresence() throws {
        let source = InMemoryPersistentKeyValueStore()
        let destination = InMemoryPersistentKeyValueStore()
        let optional = PersistentKey<Int?>("optional", defaultValue: 7)

        source.set(optional, to: nil)

        XCTAssertNotNil(try source.migrationSnapshot(for: optional.id))
        XCTAssertNoThrow(try source.copy(optional, to: destination, onConflict: .keepDestination))
        XCTAssertNil(destination.get(optional))

        let absent = PersistentKey("absent", defaultValue: 8)

        XCTAssertNil(try source.migrationSnapshot(for: absent.id))

        let absentReport = try source.copy(absent, to: destination, onConflict: .keepDestination)

        if case .sourceAbsent = absentReport.outcomes[0].status {
        } else {
            XCTFail()
        }
    }

    func testSameUserDefaultsDomainRejected() throws {
        let name = "MigrationAdapterTests.alias.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!

        defer {
            defaults.removePersistentDomain(forName: name)
        }

        let a = UserDefaultsMigrationBackend(userDefaults: defaults, domainName: name)
        let b = UserDefaultsMigrationBackend(userDefaults: defaults, domainName: name)
        let key = PersistentKey("alias", defaultValue: 0)

        defaults.set(1, forKey: key.id)

        XCTAssertThrowsError(try a.move(key, to: b, onConflict: .keepBoth))
        XCTAssertEqual(defaults.integer(forKey: key.id), 1)
    }

    func testSnapshotTokensRejectWrongKeyAndStore() throws {
        let first = InMemoryPersistentKeyValueStore()
        let second = InMemoryPersistentKeyValueStore()
        let key = PersistentKey("token", defaultValue: 0)

        first.set(key, to: 1)
        let snapshot = try XCTUnwrap(first.migrationSnapshot(for: key.id))

        XCTAssertThrowsError(try second.migrationValue(for: key, in: snapshot))
        XCTAssertThrowsError(try first.migrationSnapshotIsCurrent(snapshot, for: "other"))
    }

    @available(watchOS 9.0, *)
    func testUbiquitousKeyLengthBoundary() throws {
        let raw = StrictMigrationUbiquitousStore()
        let store = UbiquitousKeyValueMigrationBackend(
            store: raw,
            identity: .init(namespace: "test", identifier: UUID().uuidString)
        )
        let key128 = String(repeating: "x", count: 128)
        let key129 = String(repeating: "x", count: 129)

        XCTAssertNoThrow(try store.prepareMigrationWrite(1, for: PersistentKey(key128, defaultValue: 0)))
        XCTAssertThrowsError(try store.prepareMigrationWrite(1, for: PersistentKey(key129, defaultValue: 0)))
    }

    @available(watchOS 9.0, *)
    func testUbiquitousQuotaRejectedBeforeWrite() throws {
        let raw = StrictMigrationUbiquitousStore()
        let store = UbiquitousKeyValueMigrationBackend(
            store: raw,
            identity: .init(namespace: "test", identifier: UUID().uuidString)
        )
        let key = PersistentKey("cloud.large", defaultValue: Data())

        XCTAssertThrowsError(try store.prepareMigrationWrite(Data(repeating: 1, count: 1_048_577), for: key))
        XCTAssertNil(raw.storedValue(for: key.id))
    }

    @available(watchOS 9.0, *)
    func testUbiquitousRejectedWritePreservesDestination() throws {
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
        let report = try source.copy(key, to: destination, onConflict: .overwriteDestination)

        if case .failed = report.outcomes[0].status {
        } else {
            XCTFail()
        }

        XCTAssertEqual(raw.storedValue(for: key.id) as? Int64, 8)
    }

    @available(watchOS 9.0, *)
    func testUbiquitousStoreDoesNotSynchronize() throws {
        let raw = StrictMigrationUbiquitousStore()
        let store = UbiquitousKeyValueMigrationBackend(
            store: raw,
            identity: .init(namespace: "test", identifier: UUID().uuidString)
        )
        let key = PersistentKey("cloud", defaultValue: 0)

        raw.set(Int64(4), forKey: key.id)
        let destination = InMemoryPersistentKeyValueStore()

        XCTAssertNoThrow(try store.copy(key, to: destination, onConflict: .keepDestination))
        XCTAssertEqual(raw.synchronizeCount, 0)
    }

    @available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
    func testUserDefaultsCodableCodecCrossSuite() throws {
        let source = try defaults("codec.source")
        let destination = try defaults("codec.destination")
        let key = PersistentKey(
            "codec.cross",
            defaultValue: CodableValue(name: "", count: 0),
            representation: CodablePersistentKeyValueRepresentation<CodableValue, JSONEncoder, JSONDecoder>()
        )
        source.userDefaults.set(try JSONEncoder().encode(CodableValue(name: "encoded", count: 9)), forKey: key.id)

        XCTAssertNoThrow(try source.copy(key, to: destination, onConflict: .keepDestination))

        let data = try XCTUnwrap(destination.userDefaults.data(forKey: key.id))

        XCTAssertEqual(
            try JSONDecoder().decode(CodableValue.self, from: data),
            CodableValue(name: "encoded", count: 9)
        )
    }

    func testUserDefaultsCopyAndMoveBetweenSuites() throws {
        let sourceName = "MigrationAdapterTests.source.\(UUID().uuidString)"
        let destinationName = "MigrationAdapterTests.destination.\(UUID().uuidString)"
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

        XCTAssertNoThrow(try source.copy(key, to: destination, onConflict: .keepDestination))
        XCTAssertEqual(destinationDefaults.string(forKey: key.id), "hello")
        XCTAssertNoThrow(try source.move(key, to: destination, onConflict: .overwriteDestination))
        XCTAssertNil(sourceDefaults.object(forKey: key.id))
    }

    func testUserDefaultsUsesPersistedDomainOnly() throws {
        let name = "MigrationAdapterTests.persisted.\(UUID().uuidString)"
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

    private func defaults(_ suffix: String = #function) throws -> UserDefaultsMigrationBackend {
        let name = "MigrationAdapterTests.\(suffix).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!

        addTeardownBlock {
            UserDefaults(suiteName: name)?.removePersistentDomain(forName: name)
        }

        return UserDefaultsMigrationBackend(userDefaults: defaults, domainName: name)
    }
}

// MARK: - Codable Value Definition

extension MigrationAdapterTests {
    private struct CodableValue: Codable, Equatable, Sendable {
        let name: String
        let count: Int
    }
}

extension MigrationAdapterTests {
    private struct NonEquatableValue: Codable, Sendable {
        let value: String
    }
}
