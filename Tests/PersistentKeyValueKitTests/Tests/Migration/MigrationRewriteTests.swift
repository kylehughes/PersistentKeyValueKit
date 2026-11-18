import Combine
import CoreFoundation
import Foundation
import XCTest

@testable import PersistentKeyValueKit

/// Covers items that rewrite a key in place under its own identifier within one store.
///
/// Rewrites are supported in `UserDefaults` and `NSUbiquitousKeyValueStore` and rejected in an in-memory store.
@available(watchOS 9.0, *)
final class MigrationRewriteTests: XCTestCase {
    // MARK: Tests

    func testOverlapRulesStillApplyToRewrites() throws {
        for store in try stores() {
            let a = PersistentKey<Int>("key:\(#function).a", defaultValue: 0)
            let b = PersistentKey<Int>("key:\(#function).b", defaultValue: 0)
            let c = PersistentKey<Int>("key:\(#function).c", defaultValue: 0)
            let aText = PersistentKey<String>(a.id, defaultValue: "")
            let rewrite = PersistentKeyMigrationItem.key(a, to: aText) {
                String($0 + 1)
            }

            store.store.set(a, to: 1)
            store.store.set(b, to: 2)

            for items in [[rewrite, .key(b, to: a)], [.key(b, to: a), rewrite]] {
                XCTAssertThrowsError(
                    try store.store.move(
                        items: items,
                        to: store.store,
                        onConflict: .overwriteDestination,
                        tracking: .untracked
                    ),
                    store.name
                ) {
                    XCTAssertEqual($0 as? PersistentKeyMigrationError, .duplicateKey(a.id), store.name)
                }
            }

            for items in [[rewrite, .key(a, to: c)], [.key(a, to: c), rewrite]] {
                XCTAssertThrowsError(
                    try store.store.move(
                        items: items,
                        to: store.store,
                        onConflict: .overwriteDestination,
                        tracking: .untracked
                    ),
                    store.name
                ) {
                    XCTAssertEqual($0 as? PersistentKeyMigrationError, .duplicateKey(a.id), store.name)
                }
            }

            XCTAssertEqual(store.store.get(a), 1, store.name)
            XCTAssertEqual(store.store.get(b), 2, store.name)

            let report = try store.store.move(
                items: [.key(b, to: c), rewrite],
                to: store.store,
                onConflict: .overwriteDestination,
                tracking: .untracked
            )

            XCTAssertEqual(report.outcomes.map(\.status), [.moved, .rewritten], store.name)
            XCTAssertEqual(store.store.get(aText), "2", store.name)
            XCTAssertEqual(store.store.get(c), 2, store.name)
            XCTAssertNil(store.rawValue(b.id), store.name)
            store.store.remove(aText)
            store.store.remove(c)
        }
    }

    func testPlainSameKeyItemsStillThrowSameStore() throws {
        let memory = InMemoryPersistentKeyValueStore()
        let memoryStore = TestStore(
            name: "memory",
            rawValue: memory.object(forKey:),
            reloadSerialized: { _ in
            },
            store: memory
        )

        for store in try stores() + [memoryStore] {
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

    func testRewriteInAnInMemoryStoreThrowsSameStoreBeforeReadingAnyKey() throws {
        let legacy = PersistentKey<Int>("key:\(#function).legacy", defaultValue: 0)
        let current = PersistentKey<String>(legacy.id, defaultValue: "")
        let renamedSource = PersistentKey<Int>("key:\(#function).renamedSource", defaultValue: 0)
        let renamedDestination = PersistentKey<Int>("key:\(#function).renamedDestination", defaultValue: 0)
        let migrationID = "\(#function)"
        let runs = Counter()
        // The rename comes first, so it would run if the batch started before the rewrite was rejected.
        let items: [PersistentKeyMigrationItem] = [
            .key(renamedSource, to: renamedDestination),
            .key(legacy, to: current) {
                runs.increment()
                return String($0)
            },
        ]

        for (name, operation) in Operation.all {
            // Reading the completion marker, which is not a `Bool`, would throw `invalidCompletionRecord`.
            for tracking in [PersistentKeyMigrationTracking.untracked, .once(id: migrationID)] {
                let store = InMemoryPersistentKeyValueStore()
                let markerID = PersistentKey<Bool>.isMigrationCompleted(id: migrationID).id

                store.set(legacy, to: 4)
                store.set(renamedSource, to: 5)
                store.set("not a marker", forKey: markerID)

                XCTAssertThrowsError(try operation.run(items: items, in: store, tracking: tracking), name) {
                    XCTAssertEqual($0 as? PersistentKeyMigrationError, .sameStore, name)
                }

                XCTAssertEqual(store.get(legacy), 4, name)
                XCTAssertEqual(store.get(renamedSource), 5, name)
                XCTAssertNil(store.object(forKey: renamedDestination.id), name)
                XCTAssertEqual(store.object(forKey: markerID) as? String, "not a marker", name)
            }
        }

        XCTAssertEqual(runs.value, 0)
    }

    func testRewriteChangesRepresentationInPlaceUnderEveryPolicy() throws {
        for store in try stores() {
            for (name, operation) in Operation.all {
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
        for testStore in try stores() {
            let store = testStore.store
            let name = testStore.name
            let key = PersistentKey<Int>("key:\(#function)", defaultValue: 0)
            let stringKey = PersistentKey<String>(key.id, defaultValue: "")
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

            XCTAssertEqual(absent.outcomes.map(\.status), [.sourceAbsent], name)
            XCTAssertEqual(runs.value, 0, name)

            store.set(key, to: 5)

            let transformFailure = try store.move(
                .key(key, to: key) { _ in
                    throw RewriteFailure()
                },
                to: store,
                onConflict: .overwriteDestination,
                tracking: .untracked
            )

            XCTAssertEqual(transformFailure.outcomes.map(\.status), [.failed(.transform)], name)
            XCTAssertTrue(transformFailure.outcomes[0].error is RewriteFailure, name)
            XCTAssertEqual(store.get(key), 5, name)

            let changed = try store.move(
                .key(key, to: stringKey) {
                    box.store.set(key, to: 6)
                    return String($0 + 1)
                },
                to: store,
                onConflict: .overwriteDestination,
                tracking: .untracked
            )

            XCTAssertEqual(changed.outcomes.map(\.status), [.failed(.write)], name)
            XCTAssertEqual(changed.outcomes[0].error as? PersistentKeyMigrationError, .destinationChanged, name)
            XCTAssertEqual(store.get(key), 6, name)

            store.set(stringKey, to: "text")

            let decodeFailure = try store.copy(
                .key(key, to: key) {
                    $0
                },
                to: store,
                onConflict: .overwriteDestination,
                tracking: .once(id: "\(#function).\(name)")
            )

            XCTAssertEqual(decodeFailure.outcomes.map(\.status), [.failed(.decode)], name)
            XCTAssertEqual(decodeFailure.completion, .notRecorded, name)
            XCTAssertEqual(store.get(stringKey), "text", name)
            store.remove(stringKey)
        }
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

    func testRewriteRecognizedWhileItsDecoderChangesTheValueFails() throws {
        for store in try stores() {
            let id = "key:\(#function)"
            let legacy = PersistentKey<Int>(id, defaultValue: -1)
            let box = UncheckedStore(store.store)
            let current = PersistentKey<String>(
                id,
                defaultValue: "",
                representation: ReentrantStringCodec {
                    box.store.set(legacy, to: 88)
                }
            )
            let migrationID = "\(#function).\(store.name)"
            let item = PersistentKeyMigrationItem.key(legacy, to: current) {
                String($0)
            }

            store.store.set(current, to: "already")

            let report = try store.store.copy(
                item,
                to: store.store,
                onConflict: .overwriteDestination,
                tracking: .once(id: migrationID)
            )

            XCTAssertEqual(report.outcomes.map(\.status), [.failed(.write)], store.name)
            XCTAssertEqual(report.outcomes.first?.error as? PersistentKeyMigrationError, .destinationChanged, store.name)
            XCTAssertEqual(report.completion, .notRecorded, store.name)
            XCTAssertEqual(store.store.get(legacy), 88, store.name)

            let retried = try store.store.copy(
                item,
                to: store.store,
                onConflict: .overwriteDestination,
                tracking: .once(id: migrationID)
            )

            XCTAssertEqual(retried.outcomes.map(\.status), [.rewritten], store.name)
            XCTAssertEqual(retried.completion, .recorded, store.name)
            XCTAssertEqual(store.rawValue(id) as? String, "88", store.name)
            store.store.remove(legacy)
            store.store.remove(.isMigrationCompleted(id: migrationID))
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

    func testRewriteThatARetryInAnotherProcessWouldConvertAgainFailsBeforeWriting() throws {
        for store in try stores() {
            let id = "key:\(#function).distance"
            let meters = PersistentKey(id, defaultValue: 0, representation: WideIntegerCodec())
            let decimeters = PersistentKey(id, defaultValue: 0, representation: NarrowIntegerCodec())
            let gate = PersistentKey<Int>("key:\(#function).gate", defaultValue: 0)
            let renamed = PersistentKey<Int>("key:\(#function).renamed", defaultValue: 0)
            let migrationID = "\(#function).\(store.name)"
            let gateItem = PersistentKeyMigrationItem.key(gate, to: renamed) {
                guard $0 != 0 else {
                    throw RewriteFailure()
                }

                return $0
            }
            let items: [PersistentKeyMigrationItem] = [
                .key(meters, to: decimeters) {
                    $0 * 10
                },
                gateItem,
            ]

            store.store.set(meters, to: 12_345)
            store.store.set(gate, to: 0)

            let failed = try store.store.copy(
                items: items,
                to: store.store,
                onConflict: .overwriteDestination,
                tracking: .once(id: migrationID)
            )

            try store.reloadSerialized(id)
            store.store.set(gate, to: 1)

            let retried = try store.store.copy(
                items: items,
                to: store.store,
                onConflict: .overwriteDestination,
                tracking: .once(id: migrationID)
            )

            // The writing process reads the rewritten value as a 32-bit integer, which the source rejects, but other
            // processes and later launches read a 64-bit integer, which the source accepts and would convert again.
            XCTAssertEqual(failed.outcomes.map(\.status), [.failed(.prepare), .failed(.transform)], store.name)
            XCTAssertEqual(
                failed.outcomes.first?.error as? PersistentKeyMigrationError,
                .nonIdempotentRewrite,
                store.name
            )
            XCTAssertEqual(retried.outcomes.map(\.status), [.failed(.prepare), .copied], store.name)
            XCTAssertEqual(retried.completion, .notRecorded, store.name)
            XCTAssertEqual(store.store.get(meters), 12_345, store.name)

            // Narrowing the width without changing the value is repeatable from either reading.
            let narrowed = try store.store.copy(
                items: [
                    .key(meters, to: decimeters) {
                        $0
                    },
                    gateItem,
                ],
                to: store.store,
                onConflict: .overwriteDestination,
                tracking: .untracked
            )

            XCTAssertEqual(narrowed.outcomes.map(\.status), [.rewritten, .copied], store.name)
            XCTAssertEqual(store.store.get(decimeters), 12_345, store.name)
            store.store.remove(decimeters)
            store.store.remove(gate)
            store.store.remove(renamed)
        }
    }

    func testRewriteThatARetryWouldConvertAgainFailsBeforeWriting() throws {
        for store in try stores() {
            let seconds = PersistentKey<Int>("key:\(#function).duration", defaultValue: 0)
            let milliseconds = PersistentKey<Double>(seconds.id, defaultValue: 0)
            let gate = PersistentKey<Int>("key:\(#function).gate", defaultValue: 0)
            let renamed = PersistentKey<Int>("key:\(#function).renamed", defaultValue: 0)
            let migrationID = "\(#function).\(store.name)"
            let items: [PersistentKeyMigrationItem] = [
                .key(seconds, to: milliseconds) {
                    Double($0) * 1000
                },
                .key(gate, to: renamed) {
                    guard $0 != 0 else {
                        throw RewriteFailure()
                    }

                    return $0
                },
            ]

            store.store.set(seconds, to: 3)
            store.store.set(gate, to: 0)

            let failed = try store.store.move(
                items: items,
                to: store.store,
                onConflict: .keepBoth,
                tracking: .once(id: migrationID)
            )

            store.store.set(gate, to: 1)

            let retried = try store.store.move(
                items: items,
                to: store.store,
                onConflict: .keepBoth,
                tracking: .once(id: migrationID)
            )

            // Foundation stores bridge an integral `Double` to `Int`, so a retry would multiply the value again.
            XCTAssertEqual(failed.outcomes.map(\.status), [.failed(.prepare), .failed(.transform)], store.name)
            XCTAssertEqual(
                failed.outcomes.first?.error as? PersistentKeyMigrationError,
                .nonIdempotentRewrite,
                store.name
            )
            XCTAssertEqual(retried.outcomes.map(\.status), [.failed(.prepare), .moved], store.name)
            XCTAssertEqual(retried.completion, .notRecorded, store.name)
            XCTAssertEqual(store.store.get(seconds), 3, store.name)

            let raw = try XCTUnwrap(store.rawValue(seconds.id) as? NSNumber, store.name)

            XCTAssertFalse(CFNumberIsFloatType(raw), store.name)

            store.store.remove(seconds)
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
            XCTAssertEqual(store.rawValue(id) as? String, "7", store.name)

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

    func testRewriteWithinOneStorageFormatMustBeIdempotent() throws {
        for store in try stores() {
            let id = "key:\(#function)"
            let dollars = PersistentKey<Int>(id, defaultValue: 0)
            let cents = PersistentKey<Int>(id, defaultValue: 0)
            let optional = PersistentKey<Int?>(id, defaultValue: nil)
            let runs = Counter()

            store.store.set(dollars, to: 3)

            let converted = try store.store.move(
                .key(dollars, to: cents) {
                    runs.increment()
                    return $0 * 100
                },
                to: store.store,
                onConflict: .keepBoth,
                tracking: .untracked
            )

            XCTAssertEqual(converted.outcomes.map(\.status), [.failed(.prepare)], store.name)
            XCTAssertEqual(
                converted.outcomes.first?.error as? PersistentKeyMigrationError,
                .nonIdempotentRewrite,
                store.name
            )
            XCTAssertEqual(runs.value, 2, store.name)
            XCTAssertEqual(store.store.get(dollars), 3, store.name)

            // A transform that rejects its own result cannot be repeated either.
            let validated = try store.store.copy(
                .key(dollars, to: cents) {
                    guard $0 < 10 else {
                        throw RewriteFailure()
                    }

                    return $0 * 10
                },
                to: store.store,
                onConflict: .overwriteDestination,
                tracking: .untracked
            )

            XCTAssertEqual(validated.outcomes.map(\.status), [.failed(.prepare)], store.name)
            XCTAssertEqual(
                validated.outcomes.first?.error as? PersistentKeyMigrationError,
                .nonIdempotentRewrite,
                store.name
            )
            XCTAssertEqual(store.store.get(dollars), 3, store.name)

            let clamped = try store.store.move(
                .key(dollars, to: cents) {
                    min($0, 2)
                },
                to: store.store,
                onConflict: .keepBoth,
                tracking: .untracked
            )

            XCTAssertEqual(clamped.outcomes.map(\.status), [.rewritten], store.name)
            XCTAssertEqual(store.store.get(cents), 2, store.name)

            // A Foundation store removes the key for `nil`, so a retry finds no source value.
            let cleared = try store.store.copy(
                .key(optional, to: optional) { _ in
                    nil
                },
                to: store.store,
                onConflict: .overwriteDestination,
                tracking: .untracked
            )

            XCTAssertEqual(cleared.outcomes.map(\.status), [.rewritten], store.name)
            XCTAssertNil(store.store.get(optional), store.name)
            XCTAssertNil(store.rawValue(id), store.name)
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

    /// Returns the stores that support rewrites.
    private func stores(function: String = #function) throws -> [TestStore] {
        let suiteName = stableSuiteName("MigrationRewriteTests", function: function)
        let defaults = try XCTUnwrap(UserDefaults.migratable(suiteName: suiteName))
        let cloud = StrictMigrationUbiquitousStore()

        addTeardownBlock {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }

        return [
            TestStore(
                name: "defaults",
                rawValue: {
                    defaults.persistentDomain(forName: suiteName)?[$0]
                },
                reloadSerialized: { _ in
                    let domain = try XCTUnwrap(defaults.persistentDomain(forName: suiteName))
                    let reloaded = try XCTUnwrap(try serializedReadback(of: domain) as? [String: Any])
                    defaults.setPersistentDomain(reloaded, forName: suiteName)
                },
                store: defaults
            ),
            TestStore(
                name: "cloud",
                rawValue: cloud.storedValue(for:),
                reloadSerialized: {
                    cloud.set(try serializedReadback(of: try XCTUnwrap(cloud.storedValue(for: $0))), forKey: $0)
                },
                store: cloud
            ),
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

// MARK: - Narrow Integer Codec Definition

/// Stores an integer as a 32-bit number and decodes any integer.
private struct NarrowIntegerCodec: PersistentKeyValueRepresentation {
    // MARK: Internal Instance Interface

    func decode(storageObject: Any, format: PersistentKeyValueStorageFormat) throws -> Int {
        guard let number = storageObject as? NSNumber, !CFNumberIsFloatType(number) else {
            throw PersistentKeyValueConversionError.invalidStorageValue
        }

        return number.intValue
    }

    func encode(_ value: Int, format: PersistentKeyValueStorageFormat) throws -> Any? {
        guard let value = Int32(exactly: value) else {
            throw PersistentKeyValueConversionError.encodingFailed
        }

        return NSNumber(value: value)
    }
}

// MARK: - Operation Definition

private enum Operation {
    case copy(PersistentKeyCopyConflictPolicy)
    case move(PersistentKeyMoveConflictPolicy)

    // MARK: Internal Static Interface

    /// A copy or move under every conflict policy, with a short name for key identifiers and messages.
    static let all: [(name: String, operation: Self)] = [
        ("copyKeep", .copy(.keepDestination)),
        ("copyOverwrite", .copy(.overwriteDestination)),
        ("moveKeepBoth", .move(.keepBoth)),
        ("moveKeepDestination", .move(.keepDestinationAndRemoveSource)),
        ("moveOverwrite", .move(.overwriteDestination)),
    ]

    // MARK: Internal Instance Interface

    func run(
        _ item: PersistentKeyMigrationItem,
        in store: any PersistentKeyValueStore,
        tracking: PersistentKeyMigrationTracking
    ) throws -> PersistentKeyMigrationReport {
        try run(items: [item], in: store, tracking: tracking)
    }

    func run(
        items: [PersistentKeyMigrationItem],
        in store: any PersistentKeyValueStore,
        tracking: PersistentKeyMigrationTracking
    ) throws -> PersistentKeyMigrationReport {
        switch self {
        case .copy(let policy):
            try store.copy(items: items, to: store, onConflict: policy, tracking: tracking)
        case .move(let policy):
            try store.move(items: items, to: store, onConflict: policy, tracking: tracking)
        }
    }
}

// MARK: - Reentrant String Codec Definition

/// Stores strings unchanged and runs `onDecode` each time it decodes one.
private struct ReentrantStringCodec: PersistentKeyValueRepresentation {
    let onDecode: @Sendable () -> Void

    // MARK: Internal Instance Interface

    func decode(storageObject: Any, format: PersistentKeyValueStorageFormat) throws -> String {
        guard let string = storageObject as? String else {
            throw PersistentKeyValueConversionError.invalidStorageValue
        }

        onDecode()
        return string
    }

    func encode(_ value: String, format: PersistentKeyValueStorageFormat) throws -> Any? {
        value
    }
}

// MARK: - Rewrite Failure Definition

private struct RewriteFailure: Error {
}

// MARK: - Test Store Definition

private struct TestStore {
    let name: String
    let rawValue: (String) -> Any?

    /// Replaces the stored object for a key identifier with its binary property-list round trip, as another process or
    /// a later launch reads it.
    let reloadSerialized: (String) throws -> Void

    let store: any PersistentKeyValueStore
}

// MARK: - Unchecked Store Definition

/// Carries a thread-safe store into a `@Sendable` transform that runs synchronously on the calling thread.
private final class UncheckedStore: @unchecked Sendable {
    let store: any PersistentKeyValueStore

    init(_ store: any PersistentKeyValueStore) {
        self.store = store
    }
}

// MARK: - Wide Integer Codec Definition

/// Stores an integer as a 64-bit number and decodes only 64-bit numbers.
private struct WideIntegerCodec: PersistentKeyValueRepresentation {
    // MARK: Internal Instance Interface

    func decode(storageObject: Any, format: PersistentKeyValueStorageFormat) throws -> Int {
        guard let number = storageObject as? NSNumber, CFNumberGetType(number) == .sInt64Type else {
            throw PersistentKeyValueConversionError.invalidStorageValue
        }

        return number.intValue
    }

    func encode(_ value: Int, format: PersistentKeyValueStorageFormat) throws -> Any? {
        NSNumber(value: Int64(value))
    }
}

// MARK: - Serialized Readback

/// Returns `object` after a binary property-list round trip, as another process or a later launch reads it.
private func serializedReadback(of object: Any) throws -> Any {
    let data = try PropertyListSerialization.data(fromPropertyList: object, format: .binary, options: 0)
    return try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
}
