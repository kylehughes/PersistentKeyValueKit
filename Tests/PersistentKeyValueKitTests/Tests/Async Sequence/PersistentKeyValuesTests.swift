//
//  PersistentKeyValuesTests.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 1/1/26.
//

import Foundation
import PersistentKeyValueKit
import XCTest

final class PersistentKeyValuesTests: XCTestCase {
    func test_init_storesKey() {
        let key = PersistentKey("key:\(#function)", defaultValue: "defaultValue")

        let values = PersistentKeyValues(key, store: ObservablePersistentKeyValueStore())

        XCTAssertEqual(values.key.id, key.id)
        XCTAssertEqual(values.key.defaultValue, key.defaultValue)
    }

    func test_init_emitsInitialValueDefaultsToTrue() {
        let key = PersistentKey("key:\(#function)", defaultValue: "defaultValue")

        let values = PersistentKeyValues(key, store: ObservablePersistentKeyValueStore())

        XCTAssertTrue(values.emitsInitialValue)
    }

    func test_init_emitsInitialValueCanBeFalse() {
        let key = PersistentKey("key:\(#function)", defaultValue: "defaultValue")

        let values = PersistentKeyValues(key, store: ObservablePersistentKeyValueStore(), emitsInitialValue: false)

        XCTAssertFalse(values.emitsInitialValue)
    }

    func test_values_isSendableWhenValueIsSendable() {
        let store = ObservablePersistentKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: "defaultValue")

        let values = key.values(in: store)

        assertSendableAsyncSequence(values)
    }
}

// MARK: - Iterator Tests

extension PersistentKeyValuesTests {
    func test_values_emitsDefaultValueInitially() async {
        let store = ObservablePersistentKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: "defaultValue")

        var iterator = key.values(in: store).makeAsyncIterator()

        let value = await iterator.next()

        XCTAssertEqual(value, "defaultValue")
    }

    func test_values_emitsStoredValueInitially() async {
        let store = ObservablePersistentKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: "defaultValue")

        store.set(key, to: "storedValue")

        var iterator = key.values(in: store).makeAsyncIterator()

        let value = await iterator.next()

        XCTAssertEqual(value, "storedValue")
    }

    func test_values_emitsNilInitialValueForOptionalKey() async {
        let store = ObservablePersistentKeyValueStore()
        let key = PersistentKey<String?>("key:\(#function)", defaultValue: nil)

        var iterator = key.values(in: store).makeAsyncIterator()

        switch await iterator.next() {
        case .some(.none):
            break
        default:
            XCTFail("Expected initial nil value.")
        }
    }

    func test_values_canSkipInitialValue() async {
        let store = ObservablePersistentKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: "defaultValue")

        var iterator = key.values(in: store, emitsInitialValue: false).makeAsyncIterator()
        store.set(key, to: "changedValue")

        let value = await iterator.next()

        XCTAssertEqual(value, "changedValue")
    }

    func test_changes_ignoresNotificationDeliveredAfterCancellation() async {
        let store = ObservablePersistentKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: "defaultValue")
        let registered = expectation(description: "registered")

        store.retainsObservers = true
        store.onNextRegistration {
            registered.fulfill()
        }

        let task = Task {
            var iterator = key.changes(in: store).makeAsyncIterator()

            return await iterator.next()
        }

        await fulfillment(of: [registered], timeout: 5)
        task.cancel()

        let value = await task.value

        XCTAssertNil(value)
        XCTAssertEqual(store.deregistrationCount, 1)

        store.notifyRetainedObservers(keyPath: key.id)

        XCTAssertEqual(store.deregistrationCount, 1)
    }

    func test_changes_keyConvenienceSkipsInitialValue() async {
        let store = ObservablePersistentKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: "defaultValue")

        var iterator = key.changes(in: store).makeAsyncIterator()
        store.set(key, to: "changedValue")

        let value = await iterator.next()

        XCTAssertEqual(value, "changedValue")
    }

    func test_changes_keyConvenienceBuffersNewestChangeByDefault() async {
        let store = ObservablePersistentKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: "defaultValue")

        var iterator = key.changes(in: store).makeAsyncIterator()
        store.set(key, to: "firstChangedValue")
        store.set(key, to: "secondChangedValue")

        let changedValue = await iterator.next()

        XCTAssertEqual(changedValue, "secondChangedValue")
    }

    func test_changes_keyConvenienceCanUseUnboundedBufferingPolicyForRapidChanges() async {
        let store = ObservablePersistentKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: "defaultValue")

        var iterator = key.changes(in: store, bufferingPolicy: .unbounded).makeAsyncIterator()
        store.set(key, to: "firstChangedValue")
        store.set(key, to: "secondChangedValue")

        let firstChangedValue = await iterator.next()
        let secondChangedValue = await iterator.next()

        XCTAssertEqual(firstChangedValue, "firstChangedValue")
        XCTAssertEqual(secondChangedValue, "secondChangedValue")
    }

    func test_changes_storeConvenienceBuffersNewestChangeByDefault() async {
        let store = ObservablePersistentKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: "defaultValue")

        var iterator = store.changes(for: key).makeAsyncIterator()
        store.set(key, to: "firstChangedValue")
        store.set(key, to: "secondChangedValue")

        let changedValue = await iterator.next()

        XCTAssertEqual(changedValue, "secondChangedValue")
    }

    func test_changes_storeConvenienceCanUseUnboundedBufferingPolicyForRapidChanges() async {
        let store = ObservablePersistentKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: "defaultValue")

        var iterator = store.changes(for: key, bufferingPolicy: .unbounded).makeAsyncIterator()
        store.set(key, to: "firstChangedValue")
        store.set(key, to: "secondChangedValue")

        let firstChangedValue = await iterator.next()
        let secondChangedValue = await iterator.next()

        XCTAssertEqual(firstChangedValue, "firstChangedValue")
        XCTAssertEqual(secondChangedValue, "secondChangedValue")
    }

    func test_changes_storeConvenienceSkipsInitialValue() async {
        let store = ObservablePersistentKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: "defaultValue")

        var iterator = store.changes(for: key).makeAsyncIterator()
        store.set(key, to: "changedValue")

        let value = await iterator.next()

        XCTAssertEqual(value, "changedValue")
    }

    func test_values_preservesInitialValueAndBuffersNewestChangeByDefault() async {
        let store = ObservablePersistentKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: "defaultValue")

        var iterator = key.values(in: store).makeAsyncIterator()
        store.set(key, to: "firstChangedValue")
        store.set(key, to: "secondChangedValue")

        let initialValue = await iterator.next()
        let changedValue = await iterator.next()

        XCTAssertEqual(initialValue, "defaultValue")
        XCTAssertEqual(changedValue, "secondChangedValue")
    }

    func test_values_buffersNewestChangeWhenSkippingInitialValueByDefault() async {
        let store = ObservablePersistentKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: "defaultValue")

        var iterator = key.values(in: store, emitsInitialValue: false).makeAsyncIterator()
        store.set(key, to: "firstChangedValue")
        store.set(key, to: "secondChangedValue")

        let changedValue = await iterator.next()

        XCTAssertEqual(changedValue, "secondChangedValue")
    }

    func test_values_canUseUnboundedBufferingPolicyForRapidChanges() async {
        let store = ObservablePersistentKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: "defaultValue")

        var iterator = key.values(in: store, bufferingPolicy: .unbounded).makeAsyncIterator()
        store.set(key, to: "firstChangedValue")
        store.set(key, to: "secondChangedValue")

        let initialValue = await iterator.next()
        let firstChangedValue = await iterator.next()
        let secondChangedValue = await iterator.next()

        XCTAssertEqual(initialValue, "defaultValue")
        XCTAssertEqual(firstChangedValue, "firstChangedValue")
        XCTAssertEqual(secondChangedValue, "secondChangedValue")
    }

    func test_values_ignoresUnrelatedKeyPathCallbacks() async {
        let store = ObservablePersistentKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: "defaultValue")
        let unrelatedKey = PersistentKey("unrelatedKey:\(#function)", defaultValue: "unrelatedDefaultValue")

        var iterator = key.values(in: store, emitsInitialValue: false).makeAsyncIterator()
        store.notifyObservers(keyPath: unrelatedKey.id)
        store.set(key, to: "changedValue")

        let value = await iterator.next()

        XCTAssertEqual(value, "changedValue")
    }

    func test_values_ignoresNotificationsForUnrelatedKeys() async {
        let store = ObservablePersistentKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: "defaultValue")

        let values = await receivedValues(1, from: key.changes(in: store, bufferingPolicy: .unbounded)) {
            store.postToObservers(
                Notification(
                    name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                    object: store,
                    userInfo: [
                        NSUbiquitousKeyValueStoreChangedKeysKey: [
                            "unrelatedKey:\(#function)",
                        ],
                    ]
                )
            )
            store.set(key, to: "changedValue")
        }

        XCTAssertEqual(values, ["changedValue"])
    }

    func test_values_initialValueIsNotFollowedByChangesReportedBeforeIt() async {
        let store = ObservablePersistentKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: "defaultValue")

        store.onNextRegistration {
            store.set(key, to: "firstChangedValue")
            store.set(key, to: "secondChangedValue")
        }

        let values = await receivedValues(2, from: key.values(in: store, bufferingPolicy: .unbounded)) {
            store.set(key, to: "laterValue")
        }

        XCTAssertEqual(values, ["secondChangedValue", "laterValue"])
    }

    func test_changes_deliversChangesReportedDuringRegistration() async {
        let store = ObservablePersistentKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: "defaultValue")

        store.onNextRegistration {
            store.set(key, to: "changedValue")
        }

        let values = await receivedValues(1, from: key.changes(in: store, bufferingPolicy: .unbounded)) {}

        XCTAssertEqual(values, ["changedValue"])
    }
}

// MARK: - Store Integration Tests

extension PersistentKeyValuesTests {
    func test_values_userDefaultsObservesChanges() async throws {
        let (userDefaults, suiteName) = try makeUserDefaults()
        let key = PersistentKey("key:\(#function)", defaultValue: "defaultValue")
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        var iterator = key.values(in: userDefaults, emitsInitialValue: false).makeAsyncIterator()
        userDefaults.set("changedValue", forKey: key.id)

        let value = await iterator.next()

        XCTAssertEqual(value, "changedValue")
    }

    func test_values_userDefaultsObservesKeyWithPeriods() async throws {
        let (userDefaults, suiteName) = try makeUserDefaults()
        let key = PersistentKey("com.example.key.\(#function)", defaultValue: false)
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        let values = await receivedValues(3, from: key.values(in: userDefaults, bufferingPolicy: .unbounded)) {
            userDefaults.set(key, to: true)
            userDefaults.remove(key)
        }

        XCTAssertEqual(values, [false, true, false])
    }

    func test_values_userDefaultsDecoderWritingObservedKeyEmitsInReadOrder() async throws {
        let (userDefaults, suiteName) = try makeUserDefaults()
        let keyID = "key:\(#function)"
        // `UserDefaults` is thread-safe but not declared `Sendable`.
        nonisolated(unsafe) let decoderUserDefaults = userDefaults
        let key = PersistentKey(
            keyID,
            defaultValue: 0,
            representation: ProxyPersistentKeyValueRepresentation<Int, Int>(
                to: { $0 },
                from: { value in
                    // Canonicalize a legacy value by writing the observed key while it is being decoded.
                    if value == 1 {
                        decoderUserDefaults.set(2, forKey: keyID)
                    }

                    return value
                }
            )
        )
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        let values = await receivedValues(2, from: key.changes(in: userDefaults, bufferingPolicy: .unbounded)) {
            userDefaults.set(1, forKey: keyID)
        }

        XCTAssertEqual(values, [1, 2])
    }

    @available(watchOS 9.0, *)
    func test_values_ubiquitousKeyValueStoreObservesChanges() async {
        let ubiquitousKeyValueStore: NSUbiquitousKeyValueStore = MockUbiquitousKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: "defaultValue")

        var iterator = key.values(in: ubiquitousKeyValueStore, emitsInitialValue: false).makeAsyncIterator()
        ubiquitousKeyValueStore.set("changedValue", forKey: key.id)

        let value = await iterator.next()

        XCTAssertEqual(value, "changedValue")
    }

    @available(watchOS 9.0, *)
    func test_values_ubiquitousKeyValueStoreRefreshesForAccountChange() async {
        let ubiquitousKeyValueStore = MockUbiquitousKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: "defaultValue")

        let changes = key.changes(in: ubiquitousKeyValueStore, bufferingPolicy: .unbounded)

        let values = await receivedValues(1, from: changes) {
            ubiquitousKeyValueStore.storage[key.id] = "accountValue"
            NotificationCenter.default.post(
                name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                object: ubiquitousKeyValueStore,
                userInfo: [
                    NSUbiquitousKeyValueStoreChangeReasonKey: NSUbiquitousKeyValueStoreAccountChange,
                    NSUbiquitousKeyValueStoreChangedKeysKey: [
                        "unrelatedKey:\(#function)",
                    ],
                ]
            )
        }

        XCTAssertEqual(values, ["accountValue"])
    }

    @available(watchOS 9.0, *)
    func test_values_ubiquitousKeyValueStoreRefreshesWithoutChangedKeys() async {
        let ubiquitousKeyValueStore = MockUbiquitousKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: "defaultValue")

        let changes = key.changes(in: ubiquitousKeyValueStore, bufferingPolicy: .unbounded)

        let values = await receivedValues(2, from: changes) {
            ubiquitousKeyValueStore.storage[key.id] = "firstExternalValue"
            NotificationCenter.default.post(
                name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                object: ubiquitousKeyValueStore,
                userInfo: nil
            )

            ubiquitousKeyValueStore.storage[key.id] = "secondExternalValue"
            NotificationCenter.default.post(
                name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                object: ubiquitousKeyValueStore,
                userInfo: [
                    NSUbiquitousKeyValueStoreChangedKeysKey: "notAnArray",
                ]
            )
        }

        XCTAssertEqual(values, ["firstExternalValue", "secondExternalValue"])
    }

    @available(watchOS 9.0, *)
    func test_values_ubiquitousKeyValueStoreIgnoresUnrelatedNotifications() async {
        let ubiquitousKeyValueStore: NSUbiquitousKeyValueStore = MockUbiquitousKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: "defaultValue")

        var iterator = key.values(
            in: ubiquitousKeyValueStore,
            emitsInitialValue: false,
            bufferingPolicy: .unbounded
        ).makeAsyncIterator()

        NotificationCenter.default.post(
            name: NSUbiquitousKeyValueStore.didChangeInternallyNotification,
            object: ubiquitousKeyValueStore,
            userInfo: [
                NSUbiquitousKeyValueStoreChangedKeysKey: [
                    "unrelatedKey:\(#function)",
                ],
            ]
        )

        ubiquitousKeyValueStore.set("changedValue", forKey: key.id)

        let value = await iterator.next()

        XCTAssertEqual(value, "changedValue")
    }

    func test_values_inMemoryStoreOnlyEmitsInitialValue() async {
        let store = InMemoryPersistentKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: "defaultValue")

        var iterator = key.values(in: store).makeAsyncIterator()

        let value = await iterator.next()

        XCTAssertEqual(value, "defaultValue")
    }

    func test_values_inMemoryStoreObservesChanges() async {
        let store = InMemoryPersistentKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: "defaultValue")

        var iterator = key.changes(in: store).makeAsyncIterator()
        store.set(key, to: "changedValue")

        let value = await iterator.next()

        XCTAssertEqual(value, "changedValue")
    }

    func test_values_inMemoryStoreEmitsDefaultValueAfterRemove() async {
        let store = InMemoryPersistentKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: "defaultValue")

        store.set(key, to: "storedValue")

        var iterator = key.changes(in: store).makeAsyncIterator()
        store.remove(key)

        let value = await iterator.next()

        XCTAssertEqual(value, "defaultValue")
    }
}

// MARK: - Lifecycle Tests

extension PersistentKeyValuesTests {
    func test_values_releasingIteratorsWhileInMemoryStoreIsWrittenDoesNotDeadlock() {
        let store = InMemoryPersistentKeyValueStore()
        let isWriting = LockedFlag(true)
        let writersFinished = expectation(description: "Writers finished")
        let iteratorsFinished = expectation(description: "Iterators finished")

        writersFinished.expectedFulfillmentCount = 4
        iteratorsFinished.expectedFulfillmentCount = 4

        // Each write checks every registered observer on the writing thread, while the iterating threads release
        // theirs, so a write can hold the last reference to one.
        for writer in 0 ..< 4 {
            let key = PersistentKey("writer\(writer):\(#function)", defaultValue: 0)

            Thread.detachNewThread {
                var value = 0

                while isWriting.value {
                    value += 1
                    store.set(key, to: value)
                }

                writersFinished.fulfill()
            }
        }

        for iterator in 0 ..< 4 {
            let key = PersistentKey("iterator\(iterator):\(#function)", defaultValue: 0)

            Thread.detachNewThread {
                let deadline = Date(timeIntervalSinceNow: 2)

                while Date() < deadline {
                    let iterator = key.values(in: store).makeAsyncIterator()
                    withExtendedLifetime(iterator) {}
                }

                iteratorsFinished.fulfill()
            }
        }

        // A deadlock fails the waits instead of blocking the test process.
        let result = XCTWaiter.wait(for: [iteratorsFinished], timeout: 30)
        isWriting.value = false

        XCTAssertEqual(result, .completed)
        XCTAssertEqual(XCTWaiter.wait(for: [writersFinished], timeout: 30), .completed)
    }

    func test_values_concurrentCancellationAndChangeDeregistersOnce() async {
        for iteration in 0 ..< 100 {
            let store = ObservablePersistentKeyValueStore()
            let key = PersistentKey("key:\(#function):\(iteration)", defaultValue: "defaultValue")
            let registered = expectation(description: "Iterator registered \(iteration)")

            store.onNextRegistration {
                registered.fulfill()
            }

            let task = Task {
                var iterator = key.changes(in: store, bufferingPolicy: .unbounded).makeAsyncIterator()

                return await iterator.next()
            }

            await fulfillment(of: [registered], timeout: 1)

            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    task.cancel()
                }

                group.addTask {
                    store.set(key, to: "changedValue")
                }
            }

            let value = await task.value

            XCTAssertTrue(value == nil || value == "changedValue")
            XCTAssertEqual(store.deregistrationCount, 1)
        }
    }

    func test_values_cancelledTaskDoesNotReturnPendingInitialValueAndDeregisters() async {
        let store = ObservablePersistentKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: "defaultValue")

        let values = await Task {
            var iterator = key.values(in: store, bufferingPolicy: .unbounded).makeAsyncIterator()

            withUnsafeCurrentTask { task in
                task?.cancel()
            }

            let first = await iterator.next()
            store.set(key, to: "changedValue")
            let second = await iterator.next()

            return [first, second]
        }.value

        XCTAssertEqual(values, [nil, nil])
        XCTAssertEqual(store.registrationCount, 1)
        XCTAssertEqual(store.deregistrationCount, 1)
    }

    func test_values_cancelledTaskDoesNotReturnBufferedChangesAndDeregisters() async {
        let store = ObservablePersistentKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: "defaultValue")

        let values = await Task {
            var iterator = key.changes(in: store, bufferingPolicy: .unbounded).makeAsyncIterator()

            store.set(key, to: "firstChangedValue")
            store.set(key, to: "secondChangedValue")

            withUnsafeCurrentTask { task in
                task?.cancel()
            }

            let first = await iterator.next()
            let second = await iterator.next()

            return [first, second]
        }.value

        XCTAssertEqual(values, [nil, nil])
        XCTAssertEqual(store.deregistrationCount, 1)
    }

    func test_values_finishedIteratorReleasesBufferedChanges() async {
        let store = ObservablePersistentKeyValueStore()
        let key = PersistentKey(
            "key:\(#function)",
            defaultValue: ReferenceValue(0),
            representation: ProxyPersistentKeyValueRepresentation<ReferenceValue, Int>(
                to: { $0.id },
                from: { ReferenceValue($0) }
            )
        )

        let (isBufferedValueReleased, values) = await Task {
            weak var releasedValue: ReferenceValue?
            var iterator = key.changes(in: store, bufferingPolicy: .unbounded).makeAsyncIterator()

            do {
                let value = ReferenceValue(1)
                releasedValue = value

                store.set(key, to: value)
            }

            store.set(key, to: ReferenceValue(2))
            store.remove(key)

            withUnsafeCurrentTask { task in
                task?.cancel()
            }

            let values = [await iterator.next(), await iterator.next()]

            // The finished iterator is still held, but the changes it buffered are not.
            return withExtendedLifetime(iterator) {
                (releasedValue == nil, values.map { $0?.id })
            }
        }.value

        XCTAssertEqual(values, [nil, nil])
        XCTAssertTrue(isBufferedValueReleased)
        XCTAssertEqual(store.deregistrationCount, 1)
    }

    func test_values_iteratorReturnsNilInLaterTaskAfterCancellationEndsIteration() async {
        let store = ObservablePersistentKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: "defaultValue")
        // The iterator is used by one task at a time, but it is not `Sendable`.
        nonisolated(unsafe) var iterator = key.values(in: store, bufferingPolicy: .unbounded).makeAsyncIterator()

        let cancelledValue = await Task {
            withUnsafeCurrentTask { task in
                task?.cancel()
            }

            return await iterator.next()
        }.value

        store.set(key, to: "changedValue")

        let laterValue = await Task {
            await iterator.next()
        }.value

        XCTAssertNil(cancelledValue)
        XCTAssertNil(laterValue)
        XCTAssertEqual(store.deregistrationCount, 1)
    }

    func test_values_deregistersWhenIteratorDeinitializes() {
        let store = ObservablePersistentKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: "defaultValue")
        var iterator: PersistentKeyValues<PersistentKey<String>>.Iterator? = key
            .values(in: store)
            .makeAsyncIterator()

        XCTAssertNotNil(iterator)
        XCTAssertEqual(store.registrationCount, 1)

        iterator = nil

        XCTAssertEqual(store.deregistrationCount, 1)
    }

    func test_values_taskCancellationFinishesIterationAndDeregisters() async {
        let store = ObservablePersistentKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: "defaultValue")
        let initialValueReceived = expectation(description: "Initial value received")
        let taskCompleted = expectation(description: "Task completed")

        let task = Task {
            for await value in key.values(in: store) {
                XCTAssertEqual(value, "defaultValue")
                initialValueReceived.fulfill()
            }

            taskCompleted.fulfill()
        }

        await fulfillment(of: [initialValueReceived], timeout: 10)

        task.cancel()

        await fulfillment(of: [taskCompleted], timeout: 10)
        await task.value

        XCTAssertEqual(store.deregistrationCount, 1)
    }
}

// MARK: - Test Utilities

extension PersistentKeyValuesTests {
    private func assertSendableAsyncSequence<Sequence>(
        _ sequence: Sequence
    ) where Sequence: AsyncSequence & Sendable, Sequence.Element: Sendable {}

    private func makeUserDefaults(_ function: String = #function) throws -> (userDefaults: UserDefaults, suiteName: String) {
        let suiteName = stableSuiteName("PersistentKeyValuesTests", function: function)
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))

        userDefaults.removePersistentDomain(forName: suiteName)

        return (userDefaults, suiteName)
    }

    /// Iterates `sequence` until it produces `count` values, performing `action` once the iterator has registered.
    ///
    /// Waits are bounded, so a missing value fails the test instead of suspending it forever.
    private func receivedValues<Sequence>(
        _ count: Int,
        from sequence: Sequence,
        after action: () -> Void
    ) async -> [Sequence.Element] where Sequence: AsyncSequence & Sendable, Sequence.Element: Sendable {
        let registered = expectation(description: "Iterator registered")
        let received = expectation(description: "Received \(count) values")

        let task = Task {
            var iterator = sequence.makeAsyncIterator()
            var values: [Sequence.Element] = []

            registered.fulfill()

            while values.count < count, let value = try? await iterator.next() {
                values.append(value)
            }

            received.fulfill()

            return values
        }

        await fulfillment(of: [registered], timeout: 5)
        action()
        await fulfillment(of: [received], timeout: 5)
        task.cancel()

        return await task.value
    }
}

// MARK: - ReferenceValue Definition

/// A value with reference identity, so tests can observe when it is released.
private final class ReferenceValue: Sendable {
    let id: Int

    init(_ id: Int) {
        self.id = id
    }
}
