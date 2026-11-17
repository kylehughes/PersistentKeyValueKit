import Combine
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

    func testRewriteBetweenDistinctInstancesOfOneStoreThrowsSameStore() throws {
        let suiteName = stableSuiteName("MigrationRewriteTests", function: #function)
        let aliasName = suiteName.uppercased()
        let defaults = try XCTUnwrap(UserDefaults.migratable(suiteName: suiteName))
        let pairs: [(String, any PersistentKeyValueStore, any PersistentKeyValueStore)] = [
            ("same suite", defaults, try XCTUnwrap(UserDefaults.migratable(suiteName: suiteName))),
            ("case alias", defaults, try XCTUnwrap(UserDefaults.migratable(suiteName: aliasName))),
            ("cloud", StrictMigrationUbiquitousStore(), StrictMigrationUbiquitousStore()),
        ]
        let legacy = PersistentKey<Int>("key:\(#function)", defaultValue: 0)
        let current = PersistentKey<String>(legacy.id, defaultValue: "")

        addTeardownBlock {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
            UserDefaults(suiteName: aliasName)?.removePersistentDomain(forName: aliasName)
        }

        for (name, source, destination) in pairs {
            source.set(legacy, to: 42)

            XCTAssertThrowsError(
                try source.move(
                    .key(legacy, to: current) {
                        String($0)
                    },
                    to: destination,
                    onConflict: .overwriteDestination,
                    tracking: .untracked
                ),
                name
            ) {
                XCTAssertEqual($0 as? PersistentKeyMigrationError, .sameStore, name)
            }

            XCTAssertEqual(source.get(legacy), 42, name)

            let rewritten = try source.move(
                .key(legacy, to: current) {
                    String($0)
                },
                to: source,
                onConflict: .overwriteDestination,
                tracking: .untracked
            )

            XCTAssertEqual(rewritten.outcomes.map(\.status), [.rewritten], name)
            XCTAssertEqual(source.get(current), "42", name)
            source.remove(current)
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

    func testRewriteOfBooleanAsIntegerKeepsAnObserverWriteDuringReplacement() throws {
        let suiteName = stableSuiteName("MigrationRewriteTests", function: #function)
        let defaults = try XCTUnwrap(UserDefaults.migratable(suiteName: suiteName))
        let legacy = PersistentKey<Bool>("key:\(#function)", defaultValue: false)
        let current = PersistentKey<Int>(legacy.id, defaultValue: -1)
        var emissions: [Int] = []

        addTeardownBlock {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }

        defaults.set(legacy, to: true)

        let subscription = defaults.changesPublisher(for: current).sink {
            emissions.append($0)

            // Replacing a Foundation-equal value removes it first, which observers see as the key being absent.
            if defaults.persistentDomain(forName: suiteName)?[current.id] == nil {
                defaults.set(current, to: 99)
            }
        }

        defer {
            subscription.cancel()
        }

        let report = try defaults.move(
            .key(legacy, to: current) {
                $0 ? 1 : 0
            },
            to: defaults,
            onConflict: .keepBoth,
            tracking: .once(id: #function)
        )

        XCTAssertEqual(report.outcomes.map(\.status), [.failed(.write)])
        XCTAssertEqual(report.outcomes.first?.error as? PersistentKeyMigrationError, .destinationChanged)
        XCTAssertEqual(report.completion, .notRecorded)
        XCTAssertEqual(defaults.get(current), 99)
        XCTAssertEqual(emissions.last, 99)
        XCTAssertFalse(defaults.get(.isMigrationCompleted(id: #function)))
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

    func testRewriteRetriedAfterALaterFailureFindsTheValueAlreadyRewritten() throws {
        for store in try stores() {
            let legacy = PersistentKey<Int>("key:\(#function).weight", defaultValue: 0)
            let current = PersistentKey<String>(legacy.id, defaultValue: "")
            let gate = PersistentKey<Int>("key:\(#function).gate", defaultValue: 0)
            let renamed = PersistentKey<Int>("key:\(#function).renamed", defaultValue: 0)
            let migrationID = "\(#function).\(store.name)"
            let runs = Counter()
            let items: [PersistentKeyMigrationItem] = [
                .key(legacy, to: current) {
                    runs.increment()
                    return String($0 * 10)
                },
                .key(gate, to: renamed) {
                    guard $0 != 0 else {
                        throw RewriteFailure()
                    }

                    return $0
                },
            ]

            store.store.set(legacy, to: 2)
            store.store.set(gate, to: 0)

            let failed = try store.store.move(
                items: items,
                to: store.store,
                onConflict: .keepBoth,
                tracking: .once(id: migrationID)
            )

            XCTAssertEqual(failed.outcomes.map(\.status), [.rewritten, .failed(.transform)], store.name)
            XCTAssertEqual(failed.completion, .notRecorded, store.name)
            XCTAssertEqual(store.store.get(current), "20", store.name)

            store.store.set(gate, to: 1)

            let retried = try store.store.move(
                items: items,
                to: store.store,
                onConflict: .keepBoth,
                tracking: .once(id: migrationID)
            )

            XCTAssertEqual(retried.outcomes.map(\.status), [.rewritten, .moved], store.name)
            XCTAssertEqual(retried.completion, .recorded, store.name)
            XCTAssertEqual(runs.value, 1, store.name)
            XCTAssertEqual(store.rawValue(legacy.id) as? String, "20", store.name)
            XCTAssertEqual(store.store.get(renamed), 1, store.name)
            store.store.remove(current)
            store.store.remove(renamed)
            store.store.remove(.isMigrationCompleted(id: migrationID))
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

    func testTransformItemsBetweenNormalizationVariantsFollowTheStoreKeyIdentity() throws {
        let composed = PersistentKey<Int>("key:\(#function).caf\u{E9}", defaultValue: 0)
        let decomposed = PersistentKey<Int>("key:\(#function).cafe\u{301}", defaultValue: 0)
        let other = PersistentKey<Int>("key:\(#function).other", defaultValue: 0)
        let rename = PersistentKeyMigrationItem.key(composed, to: decomposed) {
            $0
        }
        let memory = InMemoryPersistentKeyValueStore()
        let suiteName = stableSuiteName("MigrationRewriteTests", function: #function)
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
