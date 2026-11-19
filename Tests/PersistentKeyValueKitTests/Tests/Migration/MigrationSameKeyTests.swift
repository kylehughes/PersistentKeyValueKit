//
//  MigrationSameKeyTests.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 11/18/26.
//

import Foundation
import XCTest

@testable import PersistentKeyValueKit

/// Covers items that map a key to its own identifier within one store, which every store rejects during setup.
@available(watchOS 9.0, *)
final class MigrationSameKeyTests: XCTestCase {
    // MARK: Tests

    func test_sameKeyItemsBetweenDistinctInstancesOfOneStore_throwSameStore() throws {
        let suiteName = stableSuiteName("MigrationSameKeyTests", function: #function)
        let aliasName = suiteName.uppercased()
        let defaults = try XCTUnwrap(UserDefaults.migratable(suiteName: suiteName))
        let pairs: [(String, any PersistentKeyValueStore, any PersistentKeyValueStore)] = [
            ("same suite", defaults, try XCTUnwrap(UserDefaults.migratable(suiteName: suiteName))),
            ("case alias", defaults, try XCTUnwrap(UserDefaults.migratable(suiteName: aliasName))),
            ("cloud", StrictMigrationUbiquitousStore(), StrictMigrationUbiquitousStore()),
        ]
        let legacy = PersistentKey<Int>("key:\(#function)", defaultValue: 0)
        let current = PersistentKey<String>(legacy.id, defaultValue: "")
        let items: [PersistentKeyMigrationItem] = [
            .key(legacy),
            .key(legacy, to: current) {
                String($0)
            },
        ]

        addTeardownBlock {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
            UserDefaults(suiteName: aliasName)?.removePersistentDomain(forName: aliasName)
        }

        for (name, source, destination) in pairs {
            source.set(legacy, to: 42)

            for (operationName, operation) in Operation.all {
                for item in items {
                    let scenario = "\(name) \(operationName)"

                    XCTAssertThrowsError(
                        try operation.run(items: [item], from: source, to: destination, tracking: .untracked),
                        scenario
                    ) {
                        XCTAssertEqual($0 as? PersistentKeyMigrationError, .sameStore, scenario)
                    }
                }
            }

            XCTAssertEqual(source.get(legacy), 42, name)
        }
    }

    func test_sameKeyItems_throwSameStoreBeforeReadingAnyKey() throws {
        let decodes = Counter()
        let transforms = Counter()
        let legacy = PersistentKey<Int>(
            "key:\(#function).legacy",
            defaultValue: -1,
            representation: CountingIntegerCodec(decodes: decodes)
        )
        let legacyText = PersistentKey<String>(legacy.id, defaultValue: "")
        let renamedSource = PersistentKey<Int>("key:\(#function).renamedSource", defaultValue: -1)
        let renamedDestination = PersistentKey<Int>("key:\(#function).renamedDestination", defaultValue: -1)
        let migrationID = "\(#function)"
        let markerID = PersistentKey<Bool>.isMigrationCompleted(id: migrationID).id
        let marker = PersistentKey<String>(markerID, defaultValue: "")
        let items: [(name: String, item: PersistentKeyMigrationItem)] = [
            ("key", .key(legacy)),
            ("keyTo", .key(legacy, to: legacy)),
            (
                "transformToSameKey",
                .key(legacy, to: legacy) {
                    transforms.increment()
                    return $0 + 1
                }
            ),
            (
                "transformToSameIdentifier",
                .key(legacy, to: legacyText) {
                    transforms.increment()
                    return String($0)
                }
            ),
        ]

        for (storeName, store) in try stores() {
            for (operationName, operation) in Operation.all {
                // Reading the completion marker, which is not a `Bool`, would throw `invalidCompletionRecord`.
                for tracking in [PersistentKeyMigrationTracking.untracked, .once(id: migrationID)] {
                    for (itemName, item) in items {
                        let scenario = "\(storeName) \(operationName) \(itemName)"

                        store.set(legacy, to: 4)
                        store.set(renamedSource, to: 5)
                        store.remove(renamedDestination)
                        store.set(marker, to: "not a marker")

                        let decodeCount = decodes.value

                        // The rename comes first, so it would run if the batch started before the item was rejected.
                        XCTAssertThrowsError(
                            try operation.run(
                                items: [.key(renamedSource, to: renamedDestination), item],
                                from: store,
                                to: store,
                                tracking: tracking
                            ),
                            scenario
                        ) {
                            XCTAssertEqual($0 as? PersistentKeyMigrationError, .sameStore, scenario)
                        }

                        XCTAssertEqual(decodes.value, decodeCount, scenario)
                        XCTAssertEqual(store.get(legacy), 4, scenario)
                        XCTAssertEqual(store.get(renamedSource), 5, scenario)
                        XCTAssertEqual(store.get(renamedDestination), -1, scenario)
                        XCTAssertEqual(store.get(marker), "not a marker", scenario)
                    }
                }
            }
        }

        XCTAssertEqual(transforms.value, 0)
    }

    func test_transformItemsBetweenNormalizationVariants_followTheStoreKeyIdentity() throws {
        let composed = PersistentKey<Int>("key:\(#function).caf\u{E9}", defaultValue: 0)
        let decomposed = PersistentKey<Int>("key:\(#function).cafe\u{301}", defaultValue: 0)
        let other = PersistentKey<Int>("key:\(#function).other", defaultValue: 0)
        let rename = PersistentKeyMigrationItem.key(composed, to: decomposed) {
            $0
        }
        let memory = InMemoryPersistentKeyValueStore()
        let suiteName = stableSuiteName("MigrationSameKeyTests", function: #function)
        let defaults = try XCTUnwrap(UserDefaults.migratable(suiteName: suiteName))

        addTeardownBlock {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }

        // The in-memory store keys entries by Swift `String`, so the two spellings name one entry.
        memory.set(composed, to: 3)

        XCTAssertThrowsError(
            try memory.move(rename, to: memory, onConflict: .overwriteDestination, tracking: .untracked)
        ) {
            XCTAssertEqual($0 as? PersistentKeyMigrationError, .sameStore)
        }

        XCTAssertThrowsError(
            try memory.move(
                items: [.key(composed, to: other), .key(decomposed, to: other)],
                to: InMemoryPersistentKeyValueStore(),
                onConflict: .overwriteDestination,
                tracking: .untracked
            )
        ) {
            XCTAssertEqual($0 as? PersistentKeyMigrationError, .duplicateKey(decomposed.id))
        }

        XCTAssertEqual(memory.get(composed), 3)

        // UserDefaults keeps literally different spellings as different keys.
        defaults.set(composed, to: 3)

        let report = try defaults.move(rename, to: defaults, onConflict: .overwriteDestination, tracking: .untracked)

        XCTAssertEqual(report.outcomes.map(\.status), [.moved])
        XCTAssertEqual(report.outcome(for: composed)?.status, .moved)
        XCTAssertNil(report.outcome(for: decomposed))
        XCTAssertNil(defaults.object(forKey: composed.id))
        XCTAssertEqual(defaults.object(forKey: decomposed.id) as? Int, 3)
    }

    // MARK: Private Instance Interface

    /// Returns one store of each built-in kind.
    private func stores(function: String = #function) throws -> [(name: String, store: any PersistentKeyValueStore)] {
        let suiteName = stableSuiteName("MigrationSameKeyTests", function: function)
        let defaults = try XCTUnwrap(UserDefaults.migratable(suiteName: suiteName))

        addTeardownBlock {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }

        return [
            ("defaults", defaults),
            ("cloud", StrictMigrationUbiquitousStore()),
            ("memory", InMemoryPersistentKeyValueStore()),
        ]
    }
}

// MARK: - Counter Definition

private final class Counter: @unchecked Sendable {
    // `lock` protects `count`.
    private let lock = NSLock()
    private var count = 0

    // MARK: Internal Instance Interface

    var value: Int {
        lock.lock()

        defer {
            lock.unlock()
        }

        return count
    }

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }
}

// MARK: - Counting Integer Codec Definition

/// Stores an integer as a number and counts each decode.
private struct CountingIntegerCodec: PersistentKeyValueRepresentation {
    let decodes: Counter

    // MARK: Internal Instance Interface

    func decode(storageObject: Any, format: PersistentKeyValueStorageFormat) throws -> Int {
        decodes.increment()

        guard let number = storageObject as? NSNumber else {
            throw PersistentKeyValueConversionError.invalidStorageValue
        }

        return number.intValue
    }

    func encode(_ value: Int, format: PersistentKeyValueStorageFormat) throws -> Any? {
        NSNumber(value: value)
    }
}

// MARK: - Operation Definition

private enum Operation {
    case copy(PersistentKeyCopyConflictPolicy)
    case move(PersistentKeyMoveConflictPolicy)

    // MARK: Internal Static Interface

    /// A copy or move under every conflict policy, with a short name for messages.
    static let all: [(name: String, operation: Self)] = [
        ("copyKeep", .copy(.keepDestination)),
        ("copyOverwrite", .copy(.overwriteDestination)),
        ("moveKeepBoth", .move(.keepBoth)),
        ("moveKeepDestination", .move(.keepDestinationAndRemoveSource)),
        ("moveOverwrite", .move(.overwriteDestination)),
    ]

    // MARK: Internal Instance Interface

    func run(
        items: [PersistentKeyMigrationItem],
        from source: any PersistentKeyValueStore,
        to destination: any PersistentKeyValueStore,
        tracking: PersistentKeyMigrationTracking
    ) throws -> PersistentKeyMigrationReport {
        switch self {
        case .copy(let policy):
            try source.copy(items: items, to: destination, onConflict: policy, tracking: tracking)
        case .move(let policy):
            try source.move(items: items, to: destination, onConflict: policy, tracking: tracking)
        }
    }
}
