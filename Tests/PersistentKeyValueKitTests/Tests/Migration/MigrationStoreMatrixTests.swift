import Foundation
import XCTest

@testable import PersistentKeyValueKit

@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
final class MigrationStoreMatrixTests: XCTestCase {
    private let boolKey = PersistentKey("matrix.bool", defaultValue: false)
    private let codableKey = PersistentKey(
        "matrix.codable",
        defaultValue: CodableValue(name: "", count: 0),
        representation: CodablePersistentKeyValueRepresentation<CodableValue, JSONEncoder, JSONDecoder>()
    )
    private let dataKey = PersistentKey("matrix.data", defaultValue: Data())
    private let doubleKey = PersistentKey("matrix.double", defaultValue: 0.0)
    private let floatKey = PersistentKey("matrix.float", defaultValue: Float(0))
    private let intKey = PersistentKey("matrix.int", defaultValue: 0)
    private let optionalKey = PersistentKey<Int?>("matrix.optional", defaultValue: nil)
    private let stringKey = PersistentKey("matrix.string", defaultValue: "")
    private let urlKey = PersistentKey("matrix.url", defaultValue: URL(string: "https://example.com")!)
    private let urlsKey = PersistentKey("matrix.urls", defaultValue: [URL]())
    private let webURLKey = PersistentKey("matrix.webURL", defaultValue: URL(string: "https://example.com")!)

    // MARK: Tests

    @available(watchOS 9.0, *)
    func testAllStorePairs() throws {
        try runPair(InMemoryPersistentKeyValueStore(), InMemoryPersistentKeyValueStore())
        try runPair(InMemoryPersistentKeyValueStore(), makeDefaults("d1"))
        try runPair(InMemoryPersistentKeyValueStore(), makeCloud())
        try runPair(makeDefaults("s0"), InMemoryPersistentKeyValueStore())
        try runPair(makeDefaults("s1"), makeDefaults("d2"))
        try runPair(makeDefaults("s2"), makeCloud())
        try runPair(makeCloud(), InMemoryPersistentKeyValueStore())
        try runPair(makeCloud(), makeDefaults("d3"))
        try runPair(makeCloud(), makeCloud())
    }

    // MARK: Private Instance Interface

    private func assertValues<S: PersistentKeyValueStore & PersistentKeyValueMigrationBackend>(_ store: S) throws {
        XCTAssertEqual(try decoded(store, boolKey), true)
        XCTAssertEqual(try decoded(store, intKey), 42)
        XCTAssertEqual(try decoded(store, doubleKey), 3.5 as Double)
        XCTAssertEqual(try decoded(store, floatKey), 2.25 as Float)
        XCTAssertEqual(try decoded(store, stringKey), "matrix")
        XCTAssertEqual(try decoded(store, dataKey), Data([1, 2, 3]))
        XCTAssertEqual(try decoded(store, urlKey), URL(fileURLWithPath: "/tmp/matrix"))
        XCTAssertEqual(try decoded(store, webURLKey), URL(string: "https://swift.org")!)
        XCTAssertEqual(try decoded(store, optionalKey), 9 as Int?)
        XCTAssertEqual(
            try decoded(store, urlsKey),
            [URL(string: "https://example.com")!, URL(fileURLWithPath: "/tmp/x")]
        )

        XCTAssertEqual(try decoded(store, codableKey), CodableValue(name: "sample", count: 7))
    }

    private func decoded<S: PersistentKeyValueStore & PersistentKeyValueMigrationBackend, K: PersistentKeyProtocol>(
        _ store: S,
        _ key: K
    ) throws -> K.Value {
        try store.migrationValue(for: key, in: XCTUnwrap(store.migrationSnapshot(for: key.id)))
    }

    @available(watchOS 9.0, *)
    private func makeCloud() -> UbiquitousKeyValueMigrationBackend {
        UbiquitousKeyValueMigrationBackend(
            store: StrictMigrationUbiquitousStore(),
            identity: .init(namespace: "matrix", identifier: UUID().uuidString)
        )
    }

    private func makeDefaults(_ suffix: String) -> UserDefaultsMigrationBackend {
        let name = "MigrationStoreMatrixTests.\(suffix).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!

        addTeardownBlock {
            UserDefaults(suiteName: name)?.removePersistentDomain(forName: name)
        }

        return UserDefaultsMigrationBackend(userDefaults: defaults, domainName: name)
    }

    private func runPair<
        S: PersistentKeyValueStore & PersistentKeyValueMigrationBackend,
        D: PersistentKeyValueStore & PersistentKeyValueMigrationBackend
    >(
        _ source: S,
        _ destination: D
    ) throws {
        let keys: [any PersistentKeyProtocol] = [
            boolKey, intKey, doubleKey, floatKey, stringKey, dataKey, urlKey, webURLKey, optionalKey, urlsKey,
            codableKey,
        ]

        try seed(source, boolKey, true)
        try seed(source, intKey, 42)
        try seed(source, doubleKey, 3.5)
        try seed(source, floatKey, 2.25)
        try seed(source, stringKey, "matrix")
        try seed(source, dataKey, Data([1, 2, 3]))
        try seed(source, urlKey, URL(fileURLWithPath: "/tmp/matrix"))
        try seed(source, webURLKey, URL(string: "https://swift.org")!)
        try seed(source, optionalKey, 9)
        try seed(source, urlsKey, [URL(string: "https://example.com")!, URL(fileURLWithPath: "/tmp/x")])
        try seed(source, codableKey, CodableValue(name: "sample", count: 7))
        try assertValues(source)

        let copied = try source.copy(keys, to: destination, onConflict: .overwriteDestination)

        XCTAssertFalse(copied.hasFailures)
        XCTAssertEqual(copied.outcomes.map(\.keyID), keys.map(\.id))
        XCTAssertTrue(
            copied.outcomes.allSatisfy {
                if case .copied = $0.status {
                    true
                } else {
                    false
                }
            }
        )
        try assertValues(destination)
        try assertValues(source)

        let moved = try source.move(keys, to: destination, onConflict: .overwriteDestination)

        XCTAssertFalse(moved.hasFailures)
        XCTAssertEqual(moved.outcomes.map(\.keyID), keys.map(\.id))
        XCTAssertTrue(
            moved.outcomes.allSatisfy {
                if case .moved = $0.status {
                    true
                } else {
                    false
                }
            }
        )
        try assertValues(destination)

        for key in keys {
            XCTAssertNil(try source.migrationSnapshot(for: key.id))
        }
    }

    private func seed<S: PersistentKeyValueStore & PersistentKeyValueMigrationBackend, K: PersistentKeyProtocol>(
        _ store: S,
        _ key: K,
        _ value: K.Value
    ) throws {
        _ = try store.commitMigrationWrite(store.prepareMigrationWrite(value, for: key), replacing: nil)
    }
}

// MARK: - Codable Value Definition

@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
extension MigrationStoreMatrixTests {
    private struct CodableValue: Codable, Equatable, Sendable {
        let name: String
        let count: Int
    }
}
