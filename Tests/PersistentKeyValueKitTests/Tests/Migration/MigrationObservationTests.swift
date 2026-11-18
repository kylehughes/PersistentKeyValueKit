import Combine
import Foundation
import XCTest

@testable import PersistentKeyValueKit

final class MigrationObservationTests: XCTestCase {
    // MARK: Tests

    @available(watchOS 9.0, *)
    func testCloudCopyPublishesOneRelatedNotification() throws {
        let source = InMemoryPersistentKeyValueStore()
        let raw = StrictMigrationUbiquitousStore()
        let destination = UbiquitousKeyValueMigrationBackend(
            store: raw,
            identity: .init(namespace: "observation", identifier: UUID().uuidString)
        )
        let key = PersistentKey<Int>(#function, defaultValue: 0)
        let other = PersistentKey<Int>("other-\(#function)", defaultValue: 0)

        source.set(key, to: 4)
        var values: [Int] = []
        var unrelated: [Int] = []
        var subscriptions = Set<AnyCancellable>()

        raw.changesPublisher(for: key).sink {
            values.append($0)
        }.store(in: &subscriptions)
        raw.changesPublisher(for: other).sink {
            unrelated.append($0)
        }.store(in: &subscriptions)
        _ = try source.copy(key, to: destination, onConflict: .overwriteDestination, tracking: .untracked)

        XCTAssertEqual(values, [4])
        XCTAssertTrue(unrelated.isEmpty)
    }

    @available(watchOS 9.0, *)
    func testCloudDestinationObserverCausesWriteFailure() throws {
        let source = InMemoryPersistentKeyValueStore()
        let raw = StrictMigrationUbiquitousStore()
        let destination = UbiquitousKeyValueMigrationBackend(
            store: raw,
            identity: .init(namespace: "observation", identifier: UUID().uuidString)
        )
        let key = PersistentKey<Int>(#function, defaultValue: 0)

        source.set(key, to: 1)
        var replaced = false
        var subscriptions = Set<AnyCancellable>()

        raw.changesPublisher(for: key).sink { _ in
            if !replaced {
                replaced = true
                raw.set(Int64(9), forKey: key.id)
            }
        }.store(in: &subscriptions)
        let report = try source.move(key, to: destination, onConflict: .overwriteDestination, tracking: .untracked)

        guard case .failed(.write) = report.outcomes[0].status, let error = report.outcomes[0].error else {
            return XCTFail("expected write failure")
        }

        XCTAssertEqual(error as? PersistentKeyMigrationError, .writeVerificationFailed)
        XCTAssertEqual(source.get(key), 1)
    }

    @available(watchOS 9.0, *)
    func testCloudSourceObserverRefillCausesRemovalFailure() throws {
        let raw = StrictMigrationUbiquitousStore()
        let source = UbiquitousKeyValueMigrationBackend(
            store: raw,
            identity: .init(namespace: "observation", identifier: UUID().uuidString)
        )
        let destination = InMemoryPersistentKeyValueStore()
        let key = PersistentKey<Int>(#function, defaultValue: 0)

        raw.set(Int64(1), forKey: key.id)
        var refilled = false
        var subscriptions = Set<AnyCancellable>()

        raw.changesPublisher(for: key).sink { _ in
            if !refilled {
                refilled = true
                raw.set(Int64(2), forKey: key.id)
            }
        }.store(in: &subscriptions)
        let report = try source.move(key, to: destination, onConflict: .overwriteDestination, tracking: .untracked)

        guard case .failed(.cleanup) = report.outcomes[0].status, let error = report.outcomes[0].error else {
            return XCTFail("expected cleanup failure")
        }

        XCTAssertEqual(error as? PersistentKeyMigrationError, .removalVerificationFailed)
        XCTAssertEqual(raw.storedValue(for: key.id) as? Int64, 2)
    }

    func testDestinationMemoryObservationCanChangeSourceBeforeCleanup() throws {
        let suiteName = stableSuiteName("MigrationObservation")
        let source = UserDefaults(suiteName: suiteName)!

        defer {
            source.removePersistentDomain(forName: suiteName)
        }

        let sourceStore = UserDefaultsMigrationBackend(
            userDefaults: source,
            domainName: suiteName
        )
        let destination = InMemoryPersistentKeyValueStore()
        let key = PersistentKey<Int>(#function, defaultValue: 0)

        source.set(key, to: 1)
        var subscriptions = Set<AnyCancellable>()
        var changed = false

        destination.changesPublisher(for: key).sink { _ in
            if !changed {
                changed = true
                source.set(key, to: 2)
            }
        }.store(in: &subscriptions)
        let report = try sourceStore.move(key, to: destination, onConflict: .overwriteDestination, tracking: .untracked)

        guard case .failed(.cleanup) = report.outcomes[0].status, let error = report.outcomes[0].error else {
            return XCTFail("expected sourceChanged")
        }

        XCTAssertEqual(error as? PersistentKeyMigrationError, .sourceChanged)
        XCTAssertEqual(source.get(key), 2)
        XCTAssertEqual(destination.get(key), 1)
    }

    func testMemoryCommittedReferenceMutatedByObserverFailsVerification() throws {
        let source = InMemoryPersistentKeyValueStore()
        let destination = InMemoryPersistentKeyValueStore()
        let key = MutableArrayKey(id: "key:\(#function)")
        var subscriptions = Set<AnyCancellable>()

        source.set(key, to: NSMutableArray(array: [1, 2]))
        destination.changesPublisher(for: key).sink {
            // In-memory stores share the reference, so this mutates the value both stores hold.
            $0.add(3)
        }.store(in: &subscriptions)

        let report = try source.move(key, to: destination, onConflict: .overwriteDestination, tracking: .untracked)

        XCTAssertEqual(report.outcomes.map(\.status), [.failed(.write)])
        XCTAssertEqual(report.outcomes.first?.error as? PersistentKeyMigrationError, .writeVerificationFailed)
        XCTAssertEqual(source.get(key), NSMutableArray(array: [1, 2, 3]))
    }

    func testMemoryPreparedCollectionChangedAfterPublishingFailsVerification() throws {
        let suiteName = stableSuiteName("MigrationObservation")
        let source = try XCTUnwrap(UserDefaults.migratable(suiteName: suiteName))
        let destination = InMemoryPersistentKeyValueStore()
        let sourceKey = PersistentKey<Int>("source:\(#function)", defaultValue: 0)
        let destinationKey = PublishedRowsKey(id: "destination:\(#function)")

        defer {
            source.removePersistentDomain(forName: suiteName)
        }

        source.set(sourceKey, to: 42)

        let report = try source.move(
            .key(sourceKey, to: destinationKey) { _ in
                let rows = PublishedRows()
                // Another writer reads the published destination and edits its nested collection the first time the
                // store reads the prepared value after publishing it.
                rows.onRead = { [unowned rows] in
                    guard destination.object(forKey: destinationKey.id) is PublishedRows, rows.row[0] as? Int == 42
                    else {
                        return
                    }

                    rows.row.replaceObject(at: 0, with: 99)
                }

                return rows
            },
            to: destination,
            onConflict: .overwriteDestination,
            tracking: .once(id: #function)
        )

        XCTAssertEqual(report.outcomes.map(\.status), [.failed(.write)])
        XCTAssertEqual(report.outcomes.first?.error as? PersistentKeyMigrationError, .writeVerificationFailed)
        XCTAssertEqual(report.completion, .notRecorded)
        XCTAssertEqual(source.get(sourceKey), 42)
        XCTAssertFalse(destination.get(.isMigrationCompleted(id: #function)))
    }

    func testMemoryCopyPublishesExactlyOneDestinationChange() throws {
        let source = InMemoryPersistentKeyValueStore()
        let destination = InMemoryPersistentKeyValueStore()
        let key = PersistentKey<Int>(#function, defaultValue: 0)

        source.set(key, to: 9)
        var values: [Int] = []
        var subscriptions = Set<AnyCancellable>()

        destination.changesPublisher(for: key).sink {
            values.append($0)
        }.store(in: &subscriptions)
        _ = try source.copy(key, to: destination, onConflict: .overwriteDestination, tracking: .untracked)

        XCTAssertEqual(values, [9])
    }

    func testMemoryCopyReplacedDestinationDeinitRemovingCopyFailsWrite() throws {
        let source = InMemoryPersistentKeyValueStore()
        let destination = InMemoryPersistentKeyValueStore()
        let key = DeinitHookEntry.key("key:\(#function)")
        let marker = PersistentKey<Bool>.isMigrationCompleted(id: #function)
        var deinitRan = false

        source.set(key, to: DeinitHookEntry("source"))
        destination.set(
            key,
            to: DeinitHookEntry("old") {
                destination.remove(key)
                deinitRan = true
            }
        )
        let report = try source.copy(
            .key(key, to: key) {
                DeinitHookEntry($0.text)
            },
            to: destination,
            onConflict: .overwriteDestination,
            tracking: .once(id: #function)
        )

        XCTAssertTrue(deinitRan)
        XCTAssertEqual(report.outcomes.map(\.status), [.failed(.write)])
        XCTAssertEqual(report.outcomes.first?.error as? PersistentKeyMigrationError, .writeVerificationFailed)
        XCTAssertEqual(report.completion, .notRecorded)
        XCTAssertEqual((source.object(forKey: key.id) as? DeinitHookEntry)?.text, "source")
        XCTAssertNil(destination.object(forKey: key.id))
        XCTAssertFalse(destination.get(marker))
    }

    func testMemoryDestinationRemovedWhileVerifyingKeptValueKeepsSource() throws {
        let source = InMemoryPersistentKeyValueStore()
        let destination = InMemoryPersistentKeyValueStore()
        let key = PublishedRowsKey(id: "key:\(#function)")
        let rows = PublishedRows()
        var reads = 0

        source.set(key, to: NSArray(array: [[7]]))
        destination.set(key, to: rows)
        rows.onRead = {
            reads += 1
        }
        _ = try destination.migrationSnapshot(for: key.id)

        // The move reads the destination this many times to capture its snapshot, and its next read compares the kept
        // value before the source is removed.
        let snapshotReads = reads

        XCTAssertGreaterThan(snapshotReads, 0)
        reads = 0
        rows.onRead = {
            reads += 1
            if reads == snapshotReads + 1 {
                destination.remove(key)
            }
        }

        let report = try source.move(
            key,
            to: destination,
            onConflict: .keepDestinationAndRemoveSource,
            tracking: .once(id: #function)
        )

        XCTAssertEqual(report.outcomes.map(\.status), [.failed(.write)])
        XCTAssertEqual(report.outcomes.first?.error as? PersistentKeyMigrationError, .destinationChanged)
        XCTAssertEqual(report.completion, .notRecorded)
        XCTAssertEqual(source.object(forKey: key.id) as? NSArray, NSArray(array: [[7]]))
        XCTAssertNil(destination.object(forKey: key.id))
        XCTAssertFalse(destination.get(.isMigrationCompleted(id: #function)))
    }

    func testMemoryDestinationRemovedWhileVerifyingMoveFailsCleanup() throws {
        let source = InMemoryPersistentKeyValueStore()
        let destination = InMemoryPersistentKeyValueStore()
        let sourceKey = PersistentKey<Int>("source:\(#function)", defaultValue: 0)
        let destinationKey = PublishedRowsKey(id: "destination:\(#function)")

        source.set(sourceKey, to: 42)

        let report = try source.move(
            .key(sourceKey, to: destinationKey) { _ in
                let rows = PublishedRows()
                // Once cleanup removes the source, the only remaining read compares the destination after cleanup.
                // Another writer removes the destination during that comparison, which still finds the expected rows.
                rows.onRead = {
                    guard source.object(forKey: sourceKey.id) == nil,
                        destination.object(forKey: destinationKey.id) != nil
                    else {
                        return
                    }

                    destination.remove(destinationKey)
                }

                return rows
            },
            to: destination,
            onConflict: .overwriteDestination,
            tracking: .once(id: #function)
        )

        XCTAssertEqual(report.outcomes.map(\.status), [.failed(.cleanup)])
        XCTAssertEqual(report.outcomes.first?.error as? PersistentKeyMigrationError, .destinationChanged)
        XCTAssertEqual(report.completion, .notRecorded)
        XCTAssertNil(source.object(forKey: sourceKey.id))
        XCTAssertNil(destination.object(forKey: destinationKey.id))
        XCTAssertFalse(destination.get(.isMigrationCompleted(id: #function)))
    }

    func testMemoryKeptDestinationRemovedByDiscardedSourceDeinitFailsCleanup() throws {
        let source = InMemoryPersistentKeyValueStore()
        let destination = InMemoryPersistentKeyValueStore()
        let key = DeinitHookEntry.key("key:\(#function)")
        let marker = PersistentKey<Bool>.isMigrationCompleted(id: #function)
        var deinitRan = false

        source.set(
            key,
            to: DeinitHookEntry("source") {
                destination.remove(key)
                deinitRan = true
            }
        )
        destination.set(key, to: DeinitHookEntry("kept"))
        let report = try source.move(
            key,
            to: destination,
            onConflict: .keepDestinationAndRemoveSource,
            tracking: .once(id: #function)
        )

        XCTAssertTrue(deinitRan)
        XCTAssertEqual(report.outcomes.map(\.status), [.failed(.cleanup)])
        XCTAssertEqual(report.outcomes.first?.error as? PersistentKeyMigrationError, .destinationChanged)
        XCTAssertEqual(report.completion, .notRecorded)
        XCTAssertNil(source.object(forKey: key.id))
        XCTAssertNil(destination.object(forKey: key.id))
        XCTAssertFalse(destination.get(marker))
    }

    func testMemoryMovePublishesSourceRemovalAndDestinationTransfer() throws {
        let source = InMemoryPersistentKeyValueStore()
        let destination = InMemoryPersistentKeyValueStore()
        let key = PersistentKey<Int>(#function, defaultValue: 0)
        let unrelated = PersistentKey<Int>("unrelated-\(#function)", defaultValue: 0)

        source.set(key, to: 7)
        var sourceValues: [Int] = []
        var destinationValues: [Int] = []
        var unrelatedValues: [Int] = []
        var subscriptions = Set<AnyCancellable>()

        source.changesPublisher(for: key).sink {
            sourceValues.append($0)
        }.store(in: &subscriptions)
        destination.changesPublisher(for: key).sink {
            destinationValues.append($0)
        }.store(
            in: &subscriptions
        )
        destination.changesPublisher(for: unrelated).sink {
            unrelatedValues.append($0)
        }.store(
            in: &subscriptions
        )
        _ = try source.move(key, to: destination, onConflict: .overwriteDestination, tracking: .untracked)

        XCTAssertEqual(sourceValues, [0])
        XCTAssertEqual(destinationValues, [7])
        XCTAssertTrue(unrelatedValues.isEmpty)
    }

    func testMemoryMoveRemovedSourceDeinitRemovingDestinationFailsCleanup() throws {
        let source = InMemoryPersistentKeyValueStore()
        let destination = InMemoryPersistentKeyValueStore()
        let key = DeinitHookEntry.key("key:\(#function)")
        let marker = PersistentKey<Bool>.isMigrationCompleted(id: #function)
        var deinitRan = false

        source.set(
            key,
            to: DeinitHookEntry("source") {
                destination.remove(key)
                deinitRan = true
            }
        )
        let report = try source.move(
            .key(key, to: key) {
                DeinitHookEntry($0.text)
            },
            to: destination,
            onConflict: .overwriteDestination,
            tracking: .once(id: #function)
        )

        XCTAssertTrue(deinitRan)
        XCTAssertEqual(report.outcomes.map(\.status), [.failed(.cleanup)])
        XCTAssertEqual(report.outcomes.first?.error as? PersistentKeyMigrationError, .destinationChanged)
        XCTAssertEqual(report.completion, .notRecorded)
        XCTAssertNil(source.object(forKey: key.id))
        XCTAssertNil(destination.object(forKey: key.id))
        XCTAssertFalse(destination.get(marker))
    }

    func testMemoryMoveRemovedSourceDeinitRestoringSourceFailsCleanup() throws {
        let source = InMemoryPersistentKeyValueStore()
        let destination = InMemoryPersistentKeyValueStore()
        let key = DeinitHookEntry.key("key:\(#function)")
        let marker = PersistentKey<Bool>.isMigrationCompleted(id: #function)
        var deinitRan = false

        source.set(
            key,
            to: DeinitHookEntry("source") {
                source.set(key, to: DeinitHookEntry("restored"))
                deinitRan = true
            }
        )
        destination.set(key, to: DeinitHookEntry("old"))
        let report = try source.move(
            .key(key, to: key) {
                DeinitHookEntry($0.text)
            },
            to: destination,
            onConflict: .overwriteDestination,
            tracking: .once(id: #function)
        )

        XCTAssertTrue(deinitRan)
        XCTAssertEqual(report.outcomes.map(\.status), [.failed(.cleanup)])
        XCTAssertEqual(report.outcomes.first?.error as? PersistentKeyMigrationError, .removalVerificationFailed)
        XCTAssertEqual(report.completion, .notRecorded)
        XCTAssertEqual((source.object(forKey: key.id) as? DeinitHookEntry)?.text, "restored")
        XCTAssertEqual((destination.object(forKey: key.id) as? DeinitHookEntry)?.text, "source")
        XCTAssertFalse(destination.get(marker))
    }

    func testMemoryMoveReplacedDestinationDeinitRemovingMoveKeepsSource() throws {
        let source = InMemoryPersistentKeyValueStore()
        let destination = InMemoryPersistentKeyValueStore()
        let key = DeinitHookEntry.key("key:\(#function)")
        let marker = PersistentKey<Bool>.isMigrationCompleted(id: #function)
        var deinitRan = false

        source.set(key, to: DeinitHookEntry("source"))
        destination.set(
            key,
            to: DeinitHookEntry("old") {
                destination.remove(key)
                deinitRan = true
            }
        )
        let report = try source.move(
            .key(key, to: key) {
                DeinitHookEntry($0.text)
            },
            to: destination,
            onConflict: .overwriteDestination,
            tracking: .once(id: #function)
        )

        XCTAssertTrue(deinitRan)
        XCTAssertEqual(report.outcomes.map(\.status), [.failed(.write)])
        XCTAssertEqual(report.outcomes.first?.error as? PersistentKeyMigrationError, .writeVerificationFailed)
        XCTAssertEqual(report.completion, .notRecorded)
        XCTAssertEqual((source.object(forKey: key.id) as? DeinitHookEntry)?.text, "source")
        XCTAssertNil(destination.object(forKey: key.id))
        XCTAssertFalse(destination.get(marker))
    }

    func testMemorySourceReferenceMutatedByDestinationObserverFailsCleanup() throws {
        let source = InMemoryPersistentKeyValueStore()
        let suiteName = stableSuiteName("MigrationObservation")
        let destination = try XCTUnwrap(UserDefaults.migratable(suiteName: suiteName))
        let key = MutableArrayKey(id: "key:\(#function)")
        var subscriptions = Set<AnyCancellable>()

        defer {
            destination.removePersistentDomain(forName: suiteName)
        }

        source.set(key, to: NSMutableArray(array: [1, 2]))
        destination.changesPublisher(for: key).sink { _ in
            source.get(key).add(3)
        }.store(in: &subscriptions)

        let report = try source.move(
            key,
            to: destination,
            onConflict: .overwriteDestination,
            tracking: .once(id: #function)
        )

        XCTAssertEqual(report.outcomes.map(\.status), [.failed(.cleanup)])
        XCTAssertEqual(report.outcomes.first?.error as? PersistentKeyMigrationError, .sourceChanged)
        XCTAssertEqual(report.completion, .notRecorded)
        XCTAssertEqual(source.get(key), NSMutableArray(array: [1, 2, 3]))
        XCTAssertEqual(destination.get(key), NSMutableArray(array: [1, 2]))
    }

    func testUnrelatedMemoryObservationStaysQuiet() throws {
        let source = InMemoryPersistentKeyValueStore()
        let destination = InMemoryPersistentKeyValueStore()
        let key = PersistentKey<Int>(#function, defaultValue: 0)
        let other = PersistentKey<Int>("other-\(#function)", defaultValue: 0)

        source.set(key, to: 3)
        var values: [Int] = []
        var subscriptions = Set<AnyCancellable>()

        destination.changesPublisher(for: other).sink {
            values.append($0)
        }.store(in: &subscriptions)
        _ = try source.copy(key, to: destination, onConflict: .overwriteDestination, tracking: .untracked)

        XCTAssertTrue(values.isEmpty)
    }

    func testUserDefaultsDestinationObserverCausesWriteFailure() throws {
        let source = InMemoryPersistentKeyValueStore()
        let suite = stableSuiteName("MigrationObservation")
        let defaults = UserDefaults(suiteName: suite)!

        defer {
            defaults.removePersistentDomain(forName: suite)
        }

        let destination = UserDefaultsMigrationBackend(userDefaults: defaults, domainName: suite)
        let key = PersistentKey<Int>(#function, defaultValue: 0)

        source.set(key, to: 1)
        var replaced = false
        var subscriptions = Set<AnyCancellable>()

        defaults.changesPublisher(for: key).sink { _ in
            if !replaced {
                replaced = true
                defaults.set(99, forKey: key.id)
            }
        }.store(in: &subscriptions)
        let report = try source.move(key, to: destination, onConflict: .overwriteDestination, tracking: .untracked)

        guard case .failed(.write) = report.outcomes[0].status, let error = report.outcomes[0].error else {
            return XCTFail("expected write failure")
        }

        XCTAssertEqual(error as? PersistentKeyMigrationError, .writeVerificationFailed)
        XCTAssertEqual(source.get(key), 1)
    }

    func testUserDefaultsMovePublishesDestinationChange() throws {
        let source = InMemoryPersistentKeyValueStore()
        let suite = "MigrationObservation.\(#function)"
        let defaults = UserDefaults(suiteName: suite)!

        defer {
            defaults.removePersistentDomain(forName: suite)
        }

        let destination = UserDefaultsMigrationBackend(userDefaults: defaults, domainName: suite)
        let key = PersistentKey<String>(#function, defaultValue: "")

        source.set(key, to: "migrated")
        var values: [String] = []
        var subscriptions = Set<AnyCancellable>()

        defaults.changesPublisher(for: key).sink {
            values.append($0)
        }.store(in: &subscriptions)
        _ = try source.move(key, to: destination, onConflict: .overwriteDestination, tracking: .untracked)

        XCTAssertEqual(values, ["migrated"])
        XCTAssertEqual(source.get(key), "")
    }
}

// MARK: - Deinit Hook Entry Definition

/// A stored reference that runs `onDeinit` when its last reference is released.
private final class DeinitHookEntry: @unchecked Sendable {
    let onDeinit: () -> Void
    let text: String

    // MARK: Internal Initialization

    init(_ text: String, onDeinit: @escaping () -> Void = {}) {
        self.text = text
        self.onDeinit = onDeinit
    }

    // MARK: Deinitialization

    deinit {
        onDeinit()
    }

    // MARK: Internal Static Interface

    static func key(_ id: String) -> PersistentKey<DeinitHookEntry> {
        PersistentKey(
            id,
            defaultValue: DeinitHookEntry("default"),
            representation: ProxyPersistentKeyValueRepresentation<DeinitHookEntry, String>(
                to: {
                    $0.text
                },
                from: {
                    DeinitHookEntry($0)
                }
            )
        )
    }
}

// MARK: - Published Rows Definition

/// An array whose one element is a mutable row of `42`, which runs `onRead` whenever its contents are read.
private final class PublishedRows: NSArray {
    var onRead: (() -> Void)?
    let row = NSMutableArray(array: [42])

    override var count: Int {
        onRead?()

        return 1
    }

    override func object(at index: Int) -> Any {
        onRead?()

        return row
    }
}

// MARK: - Published Rows Key Definition

private struct PublishedRowsKey {
    let id: String
}

// MARK: - PersistentKeyProtocol Extension

extension PublishedRowsKey: PersistentKeyProtocol {
    var defaultValue: NSArray {
        NSArray()
    }

    var representation: any PersistentKeyValueRepresentation<NSArray> {
        ProxyPersistentKeyValueRepresentation<NSArray, [[Int]]>(
            to: {
                $0 as? [[Int]]
            },
            from: {
                NSArray(array: $0)
            }
        )
    }

    func get(from defaults: UserDefaults) -> NSArray {
        representation.get(id, from: defaults) ?? defaultValue
    }

    @available(watchOS 9.0, *)
    func get(from store: NSUbiquitousKeyValueStore) -> NSArray {
        representation.get(id, from: store) ?? defaultValue
    }

    func remove(from defaults: UserDefaults) {
        defaults.removeObject(forKey: id)
    }

    @available(watchOS 9.0, *)
    func remove(from store: NSUbiquitousKeyValueStore) {
        store.removeObject(forKey: id)
    }

    func set(to value: NSArray, in defaults: UserDefaults) {
        representation.set(id, to: value, in: defaults)
    }

    @available(watchOS 9.0, *)
    func set(to value: NSArray, in store: NSUbiquitousKeyValueStore) {
        representation.set(id, to: value, in: store)
    }
}
