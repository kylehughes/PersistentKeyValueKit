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
        let aText = PersistentKey<String>(a.id, defaultValue: "")
        let rewrite = PersistentKeyMigrationItem.key(a, to: aText) {
            String($0 + 1)
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
        XCTAssertEqual(store.get(aText), "2")
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
            .key(key, to: stringKey) {
                box.store.set(key, to: 6)
                return String($0 + 1)
            },
            to: store,
            onConflict: .overwriteDestination,
            tracking: .untracked
        )

        XCTAssertEqual(changed.outcomes.map(\.status), [.failed(.write)])
        XCTAssertEqual(changed.outcomes[0].error as? PersistentKeyMigrationError, .destinationChanged)
        XCTAssertEqual(store.get(key), 6)

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

    func testRewriteRecognizedWhileItsDecoderChangesTheValueFails() throws {
        // The in-memory store skips representations, so no decoder runs there.
        for store in try stores() where store.storesFoundationObjects {
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

            if store.storesFoundationObjects {
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
            } else {
                // The in-memory store keeps a `Double`, which does not decode as an `Int`.
                XCTAssertEqual(failed.outcomes.map(\.status), [.rewritten, .failed(.transform)], store.name)
                XCTAssertEqual(retried.outcomes.map(\.status), [.rewritten, .moved], store.name)
                XCTAssertEqual(retried.completion, .recorded, store.name)
                XCTAssertEqual(store.store.get(milliseconds), 3000, store.name)
            }

            store.store.remove(seconds)
            store.store.remove(renamed)
            store.store.remove(.isMigrationCompleted(id: migrationID))
        }
    }

    func testRewriteWhoseVerificationChangesItsResultFailsBeforeWriting() throws {
        let store = InMemoryPersistentKeyValueStore()
        let key = MutableArrayKey(id: "key:\(#function)")
        let original = UncheckedReference(NSMutableArray(array: [3]))
        let migrationID = "\(#function)"

        store.set(key, to: original.value)

        // The first run copies the stored array. Verification runs the transform on the first result, which this
        // transform edits in place and returns, so both runs return the same object.
        let report = try store.move(
            .key(key, to: key) { price in
                let result = price === original.value ? price.mutableCopy() as! NSMutableArray : price

                result.replaceObject(at: 0, with: (result.object(at: 0) as! Int) * 100)

                return result
            },
            to: store,
            onConflict: .overwriteDestination,
            tracking: .once(id: migrationID)
        )

        XCTAssertEqual(report.outcomes.map(\.status), [.failed(.prepare)])
        XCTAssertEqual(report.outcomes.first?.error as? PersistentKeyMigrationError, .nonIdempotentRewrite)
        XCTAssertEqual(report.completion, .notRecorded)
        XCTAssertIdentical(store.get(key), original.value)
        XCTAssertEqual(original.value, [3])
    }

    func testRewriteOfAMutableResultThatVerificationLeavesUnchangedCommitsTheResult() throws {
        let store = InMemoryPersistentKeyValueStore()
        let key = MutableArrayKey(id: "key:\(#function)")
        let results = UncheckedReference(NSMutableArray())

        store.set(key, to: NSMutableArray(array: [3, 1, 2]))

        let report = try store.copy(
            .key(key, to: key) { numbers in
                let sorted = NSMutableArray(array: numbers.sortedArray(using: #selector(NSNumber.compare(_:))))

                results.value.add(sorted)

                return sorted
            },
            to: store,
            onConflict: .overwriteDestination,
            tracking: .untracked
        )

        XCTAssertEqual(report.outcomes.map(\.status), [.rewritten])
        XCTAssertEqual(store.get(key), [1, 2, 3])
        // The rewrite keeps the first result, whose type and identity verification does not change.
        XCTAssertEqual(results.value.count, 2)
        XCTAssertIdentical(store.get(key), results.value.firstObject as AnyObject?)
    }

    func testRewriteOfAReferenceThatCannotBeCopiedFailsBeforeWriting() throws {
        let store = InMemoryPersistentKeyValueStore()
        let key = PersistentKey<RewriteBox>(
            "key:\(#function)",
            defaultValue: RewriteBox(1),
            representation: ProxyPersistentKeyValueRepresentation<RewriteBox, Int>(
                to: {
                    $0.number
                },
                from: {
                    RewriteBox($0)
                }
            )
        )
        let original = RewriteBox(3)

        store.set(key, to: original)

        // Verification could change a reference without the store being able to tell, so the rewrite fails.
        let report = try store.copy(
            .key(key, to: key) {
                RewriteBox(min($0.number, 2))
            },
            to: store,
            onConflict: .overwriteDestination,
            tracking: .untracked
        )

        XCTAssertEqual(report.outcomes.map(\.status), [.failed(.prepare)])
        XCTAssertEqual(report.outcomes.first?.error as? PersistentKeyMigrationError, .nonIdempotentRewrite)
        XCTAssertIdentical(store.get(key), original)
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

            if store.storesFoundationObjects {
                XCTAssertNil(store.rawValue(id), store.name)
            }

            store.store.remove(optional)
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

// MARK: - Rewrite Box Definition

/// An immutable reference to a number, which the in-memory store keeps without copying.
private final class RewriteBox: Equatable, Sendable {
    let number: Int

    init(_ number: Int) {
        self.number = number
    }

    static func == (lhs: RewriteBox, rhs: RewriteBox) -> Bool {
        lhs.number == rhs.number
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

// MARK: - Unchecked Reference Definition

/// Carries a reference into a `@Sendable` transform that runs synchronously on the calling thread.
private final class UncheckedReference<Value: AnyObject>: @unchecked Sendable {
    var value: Value

    init(_ value: Value) {
        self.value = value
    }
}

// MARK: - Unchecked Store Definition

/// Carries a thread-safe store into a `@Sendable` transform that runs synchronously on the calling thread.
private final class UncheckedStore: @unchecked Sendable {
    let store: any PersistentKeyValueStore

    init(_ store: any PersistentKeyValueStore) {
        self.store = store
    }
}
