import CoreFoundation
import Foundation
import XCTest

@testable import PersistentKeyValueKit

/// Covers items that rewrite a key in place under its own identifier within one store.
@available(watchOS 9.0, *)
final class MigrationRewriteTests: XCTestCase {
    // MARK: Tests

    func testOverlapRulesStillApplyToRewrites() throws {
        let store = InMemoryPersistentKeyValueStore()
        let a = PersistentKey<Int>("key:\(#function).a", defaultValue: 0)
        let b = PersistentKey<Int>("key:\(#function).b", defaultValue: 0)
        let c = PersistentKey<Int>("key:\(#function).c", defaultValue: 0)
        let rewrite = PersistentKeyMigrationItem.key(a, to: a) {
            $0 + 1
        }

        store.set(a, to: 1)
        store.set(b, to: 2)

        for items in [[rewrite, .key(b, to: a)], [.key(b, to: a), rewrite]] {
            XCTAssertThrowsError(
                try store.move(items: items, to: store, onConflict: .overwriteDestination, tracking: .untracked)
            ) {
                XCTAssertEqual($0 as? PersistentKeyMigrationError, .duplicateKey(a.id))
            }
        }

        for items in [[rewrite, .key(a, to: c)], [.key(a, to: c), rewrite]] {
            XCTAssertThrowsError(
                try store.move(items: items, to: store, onConflict: .overwriteDestination, tracking: .untracked)
            ) {
                XCTAssertEqual($0 as? PersistentKeyMigrationError, .duplicateKey(a.id))
            }
        }

        XCTAssertEqual(store.get(a), 1)
        XCTAssertEqual(store.get(b), 2)

        let report = try store.move(
            items: [.key(b, to: c), rewrite],
            to: store,
            onConflict: .overwriteDestination,
            tracking: .untracked
        )

        XCTAssertEqual(report.outcomes.map(\.status), [.moved, .rewritten])
        XCTAssertEqual(store.get(a), 2)
        XCTAssertEqual(store.get(c), 2)
        XCTAssertNil(store.object(forKey: b.id))
    }

    func testPlainSameKeyItemsStillThrowSameStore() throws {
        for store in try stores() {
            let key = PersistentKey<Int>("key:\(#function)", defaultValue: 0)

            store.store.set(key, to: 4)

            for item in [PersistentKeyMigrationItem.key(key), .key(key, to: key)] {
                XCTAssertThrowsError(
                    try store.store.copy(item, to: store.store, onConflict: .overwriteDestination, tracking: .untracked)
                ) {
                    XCTAssertEqual($0 as? PersistentKeyMigrationError, .sameStore, store.name)
                }
            }

            XCTAssertEqual(store.store.get(key), 4, store.name)
        }
    }

    func testRewriteChangesRepresentationInPlaceUnderEveryPolicy() throws {
        let operations: [(String, Operation)] = [
            ("copyKeep", .copy(.keepDestination)),
            ("copyOverwrite", .copy(.overwriteDestination)),
            ("moveKeepBoth", .move(.keepBoth)),
            ("moveKeepDestination", .move(.keepDestinationAndRemoveSource)),
            ("moveOverwrite", .move(.overwriteDestination)),
        ]

        for store in try stores() {
            for (name, operation) in operations {
                let id = "key:\(#function).\(name)"
                let legacy = PersistentKey<Int>(id, defaultValue: 0)
                let current = PersistentKey<String>(id, defaultValue: "")
                let migrationID = "\(#function).\(store.name).\(name)"
                let scenario = "\(store.name) \(name)"

                store.store.set(legacy, to: 2)

                let report = try operation.run(
                    .key(legacy, to: current) {
                        String($0 * 10)
                    },
                    in: store.store,
                    tracking: .once(id: migrationID)
                )

                XCTAssertEqual(report.outcomes.map(\.status), [.rewritten], scenario)
                XCTAssertEqual(report.outcomes.first?.sourceKeyID, id, scenario)
                XCTAssertEqual(report.outcomes.first?.destinationKeyID, id, scenario)
                XCTAssertEqual(report.completion, .recorded, scenario)
                XCTAssertTrue(report.isComplete, scenario)
                XCTAssertEqual(store.store.get(current), "20", scenario)
                XCTAssertEqual(store.rawValue(id) as? String, "20", scenario)
                XCTAssertTrue(store.store.get(.isMigrationCompleted(id: migrationID)), scenario)

                let repeated = try operation.run(
                    .key(legacy, to: current) {
                        String($0 * 10)
                    },
                    in: store.store,
                    tracking: .once(id: migrationID)
                )

                XCTAssertEqual(repeated.completion, .alreadyRecorded, scenario)
                XCTAssertEqual(store.store.get(current), "20", scenario)
                store.store.remove(current)
                store.store.remove(.isMigrationCompleted(id: migrationID))
            }
        }
    }

    func testRewriteFailuresLeaveTheStoredValue() throws {
        let store = InMemoryPersistentKeyValueStore()
        let key = PersistentKey<Int>("key:\(#function)", defaultValue: 0)
        let box = UncheckedStore(store)
        let runs = Counter()

        let absent = try store.copy(
            .key(key, to: key) {
                runs.increment()
                return $0
            },
            to: store,
            onConflict: .overwriteDestination,
            tracking: .untracked
        )

        XCTAssertEqual(absent.outcomes.map(\.status), [.sourceAbsent])
        XCTAssertEqual(runs.value, 0)

        store.set(key, to: 5)

        let transformFailure = try store.move(
            .key(key, to: key) { _ in
                throw RewriteFailure()
            },
            to: store,
            onConflict: .overwriteDestination,
            tracking: .untracked
        )

        XCTAssertEqual(transformFailure.outcomes.map(\.status), [.failed(.transform)])
        XCTAssertTrue(transformFailure.outcomes[0].error is RewriteFailure)
        XCTAssertEqual(store.get(key), 5)

        let changed = try store.move(
            .key(key, to: key) {
                box.store.set(key, to: 6)
                return $0 + 1
            },
            to: store,
            onConflict: .overwriteDestination,
            tracking: .untracked
        )

        XCTAssertEqual(changed.outcomes.map(\.status), [.failed(.write)])
        XCTAssertEqual(changed.outcomes[0].error as? PersistentKeyMigrationError, .destinationChanged)
        XCTAssertEqual(store.get(key), 6)

        let stringKey = PersistentKey<String>(key.id, defaultValue: "")

        store.set(stringKey, to: "text")

        let decodeFailure = try store.copy(
            .key(key, to: key) {
                $0
            },
            to: store,
            onConflict: .overwriteDestination,
            tracking: .once(id: #function)
        )

        XCTAssertEqual(decodeFailure.outcomes.map(\.status), [.failed(.decode)])
        XCTAssertEqual(decodeFailure.completion, .notRecorded)
        XCTAssertEqual(store.get(stringKey), "text")
    }

    func testRewriteOfBooleanAsIntegerReplacesFoundationEqualValue() throws {
        for store in try stores() {
            let id = "key:\(#function)"
            let legacy = PersistentKey<Bool>(id, defaultValue: false)
            let current = PersistentKey<Int>(id, defaultValue: 0)

            store.store.set(legacy, to: true)

            let report = try store.store.move(
                .key(legacy, to: current) {
                    $0 ? 1 : 0
                },
                to: store.store,
                onConflict: .keepBoth,
                tracking: .untracked
            )

            XCTAssertEqual(report.outcomes.map(\.status), [.rewritten], store.name)
            XCTAssertEqual(store.store.get(current), 1, store.name)

            let raw = try XCTUnwrap(store.rawValue(id) as? NSNumber, store.name)

            XCTAssertNotEqual(CFGetTypeID(raw), CFBooleanGetTypeID(), store.name)
            store.store.remove(current)
        }
    }

    func testRewriteWithIdentityTransformChangesOnlyTheRepresentation() throws {
        for store in try stores() {
            let id = "key:\(#function)"
            let legacy = PersistentKey<Int>(id, defaultValue: 0)
            let current = PersistentKey<Int>(
                id,
                defaultValue: 0,
                representation: ProxyPersistentKeyValueRepresentation<Int, String>(
                    to: {
                        String($0)
                    },
                    from: {
                        Int($0)
                    }
                )
            )

            store.store.set(legacy, to: 7)

            let report = try store.store.copy(
                .key(legacy, to: current) {
                    $0
                },
                to: store.store,
                onConflict: .keepDestination,
                tracking: .untracked
            )

            XCTAssertEqual(report.outcomes.map(\.status), [.rewritten], store.name)
            XCTAssertEqual(store.store.get(current), 7, store.name)

            if store.storesFoundationObjects {
                XCTAssertEqual(store.rawValue(id) as? String, "7", store.name)
            }

            let unchanged = try store.store.copy(
                .key(current, to: current) {
                    $0
                },
                to: store.store,
                onConflict: .overwriteDestination,
                tracking: .untracked
            )

            XCTAssertEqual(unchanged.outcomes.map(\.status), [.rewritten], store.name)
            XCTAssertEqual(store.store.get(current), 7, store.name)
            store.store.remove(current)
        }
    }

    func testTransformItemsBetweenNormalizationVariantsThrowSameStore() throws {
        let store = InMemoryPersistentKeyValueStore()
        let composed = PersistentKey<Int>("caf\u{E9}", defaultValue: 0)
        let decomposed = PersistentKey<Int>("cafe\u{301}", defaultValue: 0)

        store.set(composed, to: 3)

        XCTAssertThrowsError(
            try store.move(
                .key(composed, to: decomposed) {
                    $0
                },
                to: store,
                onConflict: .overwriteDestination,
                tracking: .untracked
            )
        ) {
            XCTAssertEqual($0 as? PersistentKeyMigrationError, .sameStore)
        }

        XCTAssertEqual(store.get(composed), 3)
    }

    // MARK: Private Instance Interface

    private func stores(function: String = #function) throws -> [TestStore] {
        let suiteName = stableSuiteName("MigrationRewriteTests", function: function)
        let defaults = try XCTUnwrap(UserDefaults.migratable(suiteName: suiteName))
        let memory = InMemoryPersistentKeyValueStore()
        let cloud = StrictMigrationUbiquitousStore()

        addTeardownBlock {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }

        return [
            TestStore(name: "memory", rawValue: memory.object(forKey:), store: memory, storesFoundationObjects: false),
            TestStore(
                name: "defaults",
                rawValue: {
                    defaults.persistentDomain(forName: suiteName)?[$0]
                },
                store: defaults,
                storesFoundationObjects: true
            ),
            TestStore(name: "cloud", rawValue: cloud.storedValue(for:), store: cloud, storesFoundationObjects: true),
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

// MARK: - Operation Definition

private enum Operation {
    case copy(PersistentKeyCopyConflictPolicy)
    case move(PersistentKeyMoveConflictPolicy)

    // MARK: Internal Instance Interface

    func run(
        _ item: PersistentKeyMigrationItem,
        in store: any PersistentKeyValueStore,
        tracking: PersistentKeyMigrationTracking
    ) throws -> PersistentKeyMigrationReport {
        switch self {
        case .copy(let policy):
            try store.copy(item, to: store, onConflict: policy, tracking: tracking)
        case .move(let policy):
            try store.move(item, to: store, onConflict: policy, tracking: tracking)
        }
    }
}

// MARK: - Rewrite Failure Definition

private struct RewriteFailure: Error {
}

// MARK: - Test Store Definition

private struct TestStore {
    let name: String
    let rawValue: (String) -> Any?
    let store: any PersistentKeyValueStore
    let storesFoundationObjects: Bool
}

// MARK: - Unchecked Store Definition

/// Carries a thread-safe store into a `@Sendable` transform that runs synchronously on the calling thread.
private final class UncheckedStore: @unchecked Sendable {
    let store: InMemoryPersistentKeyValueStore

    init(_ store: InMemoryPersistentKeyValueStore) {
        self.store = store
    }
}
