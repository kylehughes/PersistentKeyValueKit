//
//  MigrationObservationTests.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 9/15/26.
//

import Combine
import Foundation
import XCTest

@testable import PersistentKeyValueKit

final class MigrationObservationTests: XCTestCase {
    // MARK: Tests

    func test_cloudCopy_publishesOneRelatedNotification() throws {
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

    func test_cloudDestinationObserver_causesWriteFailure() throws {
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

    func test_cloudSourceObserverRefill_causesRemovalFailure() throws {
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

    func test_destinationMemoryObservation_canChangeSourceBeforeCleanup() throws {
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

    func test_memoryCommittedReferenceMutatedByObserver_failsVerification() throws {
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

    func test_memoryPreparedCollectionChangedAfterPublishing_failsVerification() throws {
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

    func test_memoryCopy_keptDestinationRemovedByReleasedSourceDeinit_failsWrite() throws {
        let source = InMemoryPersistentKeyValueStore()
        let destination = InMemoryPersistentKeyValueStore()
        let sourceKey = DeinitHookEntry.key("source:\(#function)")
        let destinationKey = PublishedRowsKey(id: "destination:\(#function)")
        let rows = PublishedRows()
        var deinitRan = false

        source.set(
            sourceKey,
            to: DeinitHookEntry("source") {
                destination.remove(destinationKey)
                deinitRan = true
            }
        )
        destination.set(destinationKey, to: rows)
        // Another writer removes the source once the copy reads the kept value. The migration still holds the source's
        // value, so its `deinit` runs only when the migration releases it.
        rows.onRead = {
            source.remove(sourceKey)
        }

        let report = try source.copy(
            .key(sourceKey, to: destinationKey) { _ in
                NSArray()
            },
            to: destination,
            onConflict: .keepDestination,
            tracking: .once(id: #function)
        )

        XCTAssertTrue(deinitRan)
        XCTAssertEqual(report.outcomes.map(\.status), [.failed(.write)])
        XCTAssertEqual(report.outcomes.first?.error as? PersistentKeyMigrationError, .destinationChanged)
        XCTAssertEqual(report.completion, .notRecorded)
        XCTAssertNil(source.object(forKey: sourceKey.id))
        XCTAssertNil(destination.object(forKey: destinationKey.id))
        XCTAssertFalse(destination.get(.isMigrationCompleted(id: #function)))
    }

    func test_memoryCopy_keptDestinationRemovedWhileCapturingSnapshot_failsWrite() throws {
        let source = InMemoryPersistentKeyValueStore()
        let destination = InMemoryPersistentKeyValueStore()
        let key = PublishedRowsKey(id: "key:\(#function)")
        let rows = PublishedRows()

        source.set(key, to: NSArray(array: [[7]]))
        destination.set(key, to: rows)
        // Reading the kept value removes it, as a model behind a collection proxy can invalidate its cached entry.
        rows.onRead = {
            destination.remove(key)
        }

        let report = try source.copy(key, to: destination, onConflict: .keepDestination, tracking: .once(id: #function))

        XCTAssertEqual(report.outcomes.map(\.status), [.failed(.write)])
        XCTAssertEqual(report.outcomes.first?.error as? PersistentKeyMigrationError, .destinationChanged)
        XCTAssertEqual(report.completion, .notRecorded)
        XCTAssertEqual(source.object(forKey: key.id) as? NSArray, NSArray(array: [[7]]))
        XCTAssertNil(destination.object(forKey: key.id))
        XCTAssertFalse(destination.get(.isMigrationCompleted(id: #function)))

        let retry = try source.copy(key, to: destination, onConflict: .keepDestination, tracking: .once(id: #function))

        XCTAssertEqual(retry.outcomes.map(\.status), [.copied])
        XCTAssertEqual(retry.completion, .recorded)
        XCTAssertEqual(destination.object(forKey: key.id) as? NSArray, NSArray(array: [[7]]))
    }

    func test_memoryCopy_publishesExactlyOneDestinationChange() throws {
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

    func test_memoryCopy_replacedDestinationDeinitRemovingCopy_failsWrite() throws {
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

    func test_memoryCopy_sourceDeinitRemovingDestination_failsWrite() throws {
        let source = InMemoryPersistentKeyValueStore()
        let suiteName = stableSuiteName("MigrationObservation")
        let destination = try XCTUnwrap(UserDefaults.migratable(suiteName: suiteName))
        let sourceKey = DeinitHookEntry.key("source:\(#function)")
        let destinationKey = PersistentKey<String>("destination:\(#function)", defaultValue: "absent")
        let marker = PersistentKey<Bool>.isMigrationCompleted(id: #function)
        var deinitRan = false
        var subscriptions = Set<AnyCancellable>()

        defer {
            destination.removePersistentDomain(forName: suiteName)
        }

        source.set(
            sourceKey,
            to: DeinitHookEntry("saved") {
                destination.remove(destinationKey)
                deinitRan = true
            }
        )
        // Another writer removes the source once the copy reaches the destination. The migration still holds the
        // source's value, so its `deinit` runs only when the migration releases it.
        destination.changesPublisher(for: destinationKey).sink { value in
            guard value == "saved" else {
                return
            }

            source.remove(sourceKey)
        }.store(in: &subscriptions)

        let item = PersistentKeyMigrationItem.key(sourceKey, to: destinationKey) {
            $0.text
        }
        let report = try source.copy(
            item,
            to: destination,
            onConflict: .overwriteDestination,
            tracking: .once(id: #function)
        )

        XCTAssertTrue(deinitRan)
        XCTAssertEqual(report.outcomes.map(\.status), [.failed(.write)])
        XCTAssertEqual(report.outcomes.first?.error as? PersistentKeyMigrationError, .writeVerificationFailed)
        XCTAssertEqual(report.completion, .notRecorded)
        XCTAssertNil(source.object(forKey: sourceKey.id))
        XCTAssertNil(destination.object(forKey: destinationKey.id))
        XCTAssertFalse(destination.get(marker))

        let retry = try source.copy(
            item,
            to: destination,
            onConflict: .overwriteDestination,
            tracking: .once(id: #function)
        )

        XCTAssertEqual(retry.outcomes.map(\.status), [.sourceAbsent])
        XCTAssertNil(destination.object(forKey: destinationKey.id))
    }

    func test_memoryDestinationRemovedWhileVerifyingKeptValue_keepsSource() throws {
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

    func test_memoryDestinationRemovedWhileVerifyingMove_failsCleanup() throws {
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

    func test_memoryDestinationVerificationRestoringSource_failsMoveCleanup() throws {
        let source = InMemoryPersistentKeyValueStore()
        let destination = InMemoryPersistentKeyValueStore()
        let sourceKey = PersistentKey<Int>("source:\(#function)", defaultValue: 0)
        let destinationKey = PublishedRowsKey(id: "destination:\(#function)")

        source.set(sourceKey, to: 42)

        let report = try source.move(
            .key(sourceKey, to: destinationKey) { _ in
                let rows = PublishedRows()
                // Once cleanup removes the source, the only remaining reads compare the destination after cleanup.
                // Another writer restores the source during that comparison, which still finds the expected rows.
                rows.onRead = {
                    guard source.object(forKey: sourceKey.id) == nil else {
                        return
                    }

                    source.set(sourceKey, to: 99)
                }

                return rows
            },
            to: destination,
            onConflict: .overwriteDestination,
            tracking: .once(id: #function)
        )

        XCTAssertEqual(report.outcomes.map(\.status), [.failed(.cleanup)])
        XCTAssertEqual(report.outcomes.first?.error as? PersistentKeyMigrationError, .removalVerificationFailed)
        XCTAssertEqual(report.completion, .notRecorded)
        XCTAssertEqual(source.get(sourceKey), 99)
        XCTAssertEqual(destination.object(forKey: destinationKey.id) as? NSArray, NSArray(array: [[42]]))
        XCTAssertFalse(destination.get(.isMigrationCompleted(id: #function)))
    }

    func test_memoryKeptDestinationRemovedByDiscardedSourceDeinit_failsCleanup() throws {
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

    func test_memoryKeptDestinationVerificationRestoringSource_failsCleanup() throws {
        let source = InMemoryPersistentKeyValueStore()
        let destination = InMemoryPersistentKeyValueStore()
        let sourceKey = PersistentKey<Int>("source:\(#function)", defaultValue: 0)
        let destinationKey = PublishedRowsKey(id: "destination:\(#function)")
        let rows = PublishedRows()
        var restoreCount = 0

        source.set(sourceKey, to: 42)
        destination.set(destinationKey, to: rows)
        // Once cleanup removes the source, the only remaining reads compare the kept destination after cleanup. Another
        // writer restores the source during that comparison, which still finds the kept rows.
        rows.onRead = {
            guard source.object(forKey: sourceKey.id) == nil else {
                return
            }

            source.set(sourceKey, to: 99)
            restoreCount += 1
        }

        let report = try source.move(
            .key(sourceKey, to: destinationKey) { _ in
                NSArray()
            },
            to: destination,
            onConflict: .keepDestinationAndRemoveSource,
            tracking: .once(id: #function)
        )

        XCTAssertEqual(restoreCount, 1)
        XCTAssertEqual(report.outcomes.map(\.status), [.failed(.cleanup)])
        XCTAssertEqual(report.outcomes.first?.error as? PersistentKeyMigrationError, .removalVerificationFailed)
        XCTAssertEqual(report.completion, .notRecorded)
        XCTAssertEqual(source.get(sourceKey), 99)
        XCTAssertTrue(destination.object(forKey: destinationKey.id) as? PublishedRows === rows)
        XCTAssertFalse(destination.get(.isMigrationCompleted(id: #function)))
    }

    func test_memoryMoveKeptBoth_destinationRemovedByReleasedSourceDeinit_failsWrite() throws {
        let source = InMemoryPersistentKeyValueStore()
        let destination = InMemoryPersistentKeyValueStore()
        let sourceKey = DeinitHookEntry.key("source:\(#function)")
        let destinationKey = PublishedRowsKey(id: "destination:\(#function)")
        let rows = PublishedRows()
        var deinitRan = false

        source.set(
            sourceKey,
            to: DeinitHookEntry("source") {
                destination.remove(destinationKey)
                deinitRan = true
            }
        )
        destination.set(destinationKey, to: rows)
        // Another writer removes the source once the move reads the kept value. The migration still holds the source's
        // value, so its `deinit` runs only when the migration releases it.
        rows.onRead = {
            source.remove(sourceKey)
        }

        let report = try source.move(
            .key(sourceKey, to: destinationKey) { _ in
                NSArray()
            },
            to: destination,
            onConflict: .keepBoth,
            tracking: .once(id: #function)
        )

        XCTAssertTrue(deinitRan)
        XCTAssertEqual(report.outcomes.map(\.status), [.failed(.write)])
        XCTAssertEqual(report.outcomes.first?.error as? PersistentKeyMigrationError, .destinationChanged)
        XCTAssertEqual(report.completion, .notRecorded)
        XCTAssertNil(source.object(forKey: sourceKey.id))
        XCTAssertNil(destination.object(forKey: destinationKey.id))
        XCTAssertFalse(destination.get(.isMigrationCompleted(id: #function)))
    }

    func test_memoryMoveKeptBoth_destinationRemovedWhileCapturingSnapshot_failsWrite() throws {
        let source = InMemoryPersistentKeyValueStore()
        let destination = InMemoryPersistentKeyValueStore()
        let key = PublishedRowsKey(id: "key:\(#function)")
        let rows = PublishedRows()

        source.set(key, to: NSArray(array: [[7]]))
        destination.set(key, to: rows)
        // Reading the kept value removes it, as a model behind a collection proxy can invalidate its cached entry.
        rows.onRead = {
            destination.remove(key)
        }

        let report = try source.move(key, to: destination, onConflict: .keepBoth, tracking: .once(id: #function))

        XCTAssertEqual(report.outcomes.map(\.status), [.failed(.write)])
        XCTAssertEqual(report.outcomes.first?.error as? PersistentKeyMigrationError, .destinationChanged)
        XCTAssertEqual(report.completion, .notRecorded)
        XCTAssertEqual(source.object(forKey: key.id) as? NSArray, NSArray(array: [[7]]))
        XCTAssertNil(destination.object(forKey: key.id))
        XCTAssertFalse(destination.get(.isMigrationCompleted(id: #function)))

        let retry = try source.move(key, to: destination, onConflict: .keepBoth, tracking: .once(id: #function))

        XCTAssertEqual(retry.outcomes.map(\.status), [.moved])
        XCTAssertEqual(retry.completion, .recorded)
        XCTAssertNil(source.object(forKey: key.id))
        XCTAssertEqual(destination.object(forKey: key.id) as? NSArray, NSArray(array: [[7]]))
    }

    func test_memoryMove_publishesSourceRemovalAndDestinationTransfer() throws {
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

    func test_memoryMove_removedSourceDeinitRemovingDestination_failsCleanup() throws {
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

    func test_memoryMove_removedSourceDeinitRestoringSource_failsCleanup() throws {
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

    func test_memoryMove_replacedDestinationDeinitRemovingMove_keepsSource() throws {
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

    func test_memoryReplacedFalseMarkerDeinitRemovingRecord_failsCompletion() throws {
        let source = InMemoryPersistentKeyValueStore()
        let destination = InMemoryPersistentKeyValueStore()
        let key = PersistentKey<Int>("key:\(#function)", defaultValue: 0)
        let marker = PersistentKey<Bool>.isMigrationCompleted(id: #function)
        var deinitRan = false

        // A decimal zero reads as a `false` marker. Its associated entry runs its hook when the replaced marker is
        // released.
        do {
            let falseMarker = NSDecimalNumber(string: "0.000")

            objc_setAssociatedObject(
                falseMarker,
                &DeinitHookEntry.associationKey,
                DeinitHookEntry("marker") {
                    destination.remove(marker)
                    deinitRan = true
                },
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
            destination.set(falseMarker, forKey: marker.id)
        }

        source.set(key, to: 5)

        XCTAssertFalse(destination.get(marker))
        XCTAssertFalse(deinitRan)

        let report = try source.move(
            key,
            to: destination,
            onConflict: .overwriteDestination,
            tracking: .once(id: #function)
        )

        XCTAssertTrue(deinitRan)
        XCTAssertEqual(report.outcomes.map(\.status), [.moved])
        XCTAssertEqual(report.completion, .failed)
        XCTAssertEqual(report.completionError as? PersistentKeyMigrationError, .writeVerificationFailed)
        XCTAssertNil(destination.object(forKey: marker.id))
        XCTAssertEqual(destination.get(key), 5)
        XCTAssertNil(source.object(forKey: key.id))
    }

    func test_memorySourceReferenceMutatedByDestinationObserver_failsCleanup() throws {
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

    func test_unrelatedMemoryObservation_staysQuiet() throws {
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

    func test_userDefaultsCopy_preparedWriteReleaseRemovingDestination_failsWrite() throws {
        let source = InMemoryPersistentKeyValueStore()
        let suiteName = stableSuiteName("MigrationObservation")
        // `UserDefaults` is thread-safe but not declared `Sendable`.
        nonisolated(unsafe) let destination = try XCTUnwrap(UserDefaults.migratable(suiteName: suiteName))
        let sourceKey = PersistentKey<Int>("source:\(#function)", defaultValue: 0)
        let destinationKey = AllocatorHookNumber.key("destination:\(#function)")
        let removedDestination = LockedFlag(false)

        defer {
            destination.removePersistentDomain(forName: suiteName)
        }

        source.set(sourceKey, to: .max)
        // `UserDefaults` stores its own copy of a number, so the prepared write holds the last reference to the encoded
        // number, whose allocator's cleanup removes the destination when the migration releases the write.
        let item = PersistentKeyMigrationItem.key(sourceKey, to: destinationKey) {
            AllocatorHookNumber.make($0) {
                if destination.object(forKey: destinationKey.id) != nil {
                    destination.removeObject(forKey: destinationKey.id)
                    removedDestination.value = true
                }
            }
        }
        let report = try source.copy(
            item,
            to: destination,
            onConflict: .overwriteDestination,
            tracking: .once(id: #function)
        )

        XCTAssertTrue(removedDestination.value)
        XCTAssertEqual(report.outcomes.map(\.status), [.failed(.write)])
        XCTAssertEqual(report.outcomes.first?.error as? PersistentKeyMigrationError, .writeVerificationFailed)
        XCTAssertEqual(report.completion, .notRecorded)
        XCTAssertEqual(source.get(sourceKey), .max)
        XCTAssertNil(destination.object(forKey: destinationKey.id))
        XCTAssertFalse(destination.get(.isMigrationCompleted(id: #function)))
    }

    func test_userDefaultsCopy_sharedSourceAndWriteReleaseRemovingDestination_failsWrite() throws {
        let source = InMemoryPersistentKeyValueStore()
        let suiteName = stableSuiteName("MigrationObservation")
        let destination = try XCTUnwrap(UserDefaults.migratable(suiteName: suiteName))
        let key = AllocatorHookNumber.key("key:\(#function)")
        var removedDestination = false
        var subscriptions = Set<AnyCancellable>()

        defer {
            destination.removePersistentDomain(forName: suiteName)
        }

        // The source snapshot and the prepared write hold the same number, whose allocator's cleanup removes the
        // destination once the migration releases both.
        source.set(
            key,
            to: AllocatorHookNumber.make(.max) {
                if destination.object(forKey: key.id) != nil {
                    destination.removeObject(forKey: key.id)
                    removedDestination = true
                }
            }
        )
        // Another writer removes the source once the copy reaches the destination, so the migration holds the
        // remaining references to the number.
        destination.changesPublisher(for: key).sink { value in
            guard value.intValue == .max else {
                return
            }

            source.remove(key)
        }.store(in: &subscriptions)

        let report = try source.copy(
            key,
            to: destination,
            onConflict: .overwriteDestination,
            tracking: .once(id: #function)
        )

        XCTAssertTrue(removedDestination)
        XCTAssertEqual(report.outcomes.map(\.status), [.failed(.write)])
        XCTAssertEqual(report.outcomes.first?.error as? PersistentKeyMigrationError, .writeVerificationFailed)
        XCTAssertEqual(report.completion, .notRecorded)
        XCTAssertNil(source.object(forKey: key.id))
        XCTAssertNil(destination.object(forKey: key.id))
        XCTAssertFalse(destination.get(.isMigrationCompleted(id: #function)))
    }

    func test_userDefaultsDestinationObserver_causesWriteFailure() throws {
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

    func test_userDefaultsMove_preparedWriteReleaseRemovingDestination_keepsSource() throws {
        let source = InMemoryPersistentKeyValueStore()
        let suiteName = stableSuiteName("MigrationObservation")
        // `UserDefaults` is thread-safe but not declared `Sendable`.
        nonisolated(unsafe) let destination = try XCTUnwrap(UserDefaults.migratable(suiteName: suiteName))
        let sourceKey = PersistentKey<Int>("source:\(#function)", defaultValue: 0)
        let destinationKey = AllocatorHookNumber.key("destination:\(#function)")
        let removedDestination = LockedFlag(false)

        defer {
            destination.removePersistentDomain(forName: suiteName)
        }

        source.set(sourceKey, to: .max)
        // `UserDefaults` stores its own copy of a number, so the prepared write holds the last reference to the encoded
        // number, whose allocator's cleanup removes the destination when the migration releases the write.
        let item = PersistentKeyMigrationItem.key(sourceKey, to: destinationKey) {
            AllocatorHookNumber.make($0) {
                if destination.object(forKey: destinationKey.id) != nil {
                    destination.removeObject(forKey: destinationKey.id)
                    removedDestination.value = true
                }
            }
        }
        let report = try source.move(
            item,
            to: destination,
            onConflict: .overwriteDestination,
            tracking: .once(id: #function)
        )

        XCTAssertTrue(removedDestination.value)
        XCTAssertEqual(report.outcomes.map(\.status), [.failed(.write)])
        XCTAssertEqual(report.outcomes.first?.error as? PersistentKeyMigrationError, .writeVerificationFailed)
        XCTAssertEqual(report.completion, .notRecorded)
        XCTAssertEqual(source.get(sourceKey), .max)
        XCTAssertNil(destination.object(forKey: destinationKey.id))
        XCTAssertFalse(destination.get(.isMigrationCompleted(id: #function)))
    }

    func test_userDefaultsMove_publishesDestinationChange() throws {
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

// MARK: - Allocator Hook Number Definition

/// Creates numbers whose Core Foundation allocator runs a cleanup action when the number is deallocated.
private enum AllocatorHookNumber {
    // MARK: Internal Static Interface

    /// A key whose representation stores a number as it is, so the encoded object is the value itself.
    static func key(_ id: String) -> PersistentKey<NSNumber> {
        PersistentKey(id, defaultValue: NSNumber(value: 0), representation: Representation())
    }

    /// Returns a number for `value`, which must be too large for a tagged pointer, that runs `onRelease` when it is
    /// deallocated.
    static func make(_ value: Int, onRelease: @escaping () -> Void) -> NSNumber {
        var context = CFAllocatorContext()
        // A number releases its allocator when it is deallocated, and the allocator then releases this entry.
        context.info = Unmanaged.passRetained(DeinitHookEntry("allocator", onDeinit: onRelease)).toOpaque()
        context.release = {
            Unmanaged<DeinitHookEntry>.fromOpaque($0!).release()
        }
        context.allocate = { size, _, _ in
            malloc(size)
        }
        context.reallocate = { pointer, size, _, _ in
            realloc(pointer, size)
        }
        context.deallocate = { pointer, _ in
            free(pointer)
        }

        let allocator = CFAllocatorCreate(nil, &context).takeRetainedValue()
        var number = Int64(value)

        return CFNumberCreate(allocator, .sInt64Type, &number)
    }
}

// MARK: - Representation Extension

extension AllocatorHookNumber {
    private struct Representation: PersistentKeyValueRepresentation {
        func decode(storageObject: Any, format: PersistentKeyValueStorageFormat) throws -> NSNumber {
            guard let number = storageObject as? NSNumber else {
                throw PersistentKeyValueConversionError.invalidStorageValue
            }

            return number
        }

        func encode(_ value: NSNumber, format: PersistentKeyValueStorageFormat) throws -> Any? {
            value
        }
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

    /// The key that associates an entry with another object, so the entry is released with that object.
    nonisolated(unsafe) static var associationKey: UInt8 = 0

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

    func get(from store: NSUbiquitousKeyValueStore) -> NSArray {
        representation.get(id, from: store) ?? defaultValue
    }

    func remove(from defaults: UserDefaults) {
        defaults.removeObject(forKey: id)
    }

    func remove(from store: NSUbiquitousKeyValueStore) {
        store.removeObject(forKey: id)
    }

    func set(to value: NSArray, in defaults: UserDefaults) {
        representation.set(id, to: value, in: defaults)
    }

    func set(to value: NSArray, in store: NSUbiquitousKeyValueStore) {
        representation.set(id, to: value, in: store)
    }
}
