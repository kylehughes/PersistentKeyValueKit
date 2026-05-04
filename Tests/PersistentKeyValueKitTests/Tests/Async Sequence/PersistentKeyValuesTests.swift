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
    func test_values_ubiquitousKeyValueStoreIgnoresMalformedAndUnrelatedNotifications() async {
        let ubiquitousKeyValueStore: NSUbiquitousKeyValueStore = MockUbiquitousKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: "defaultValue")

        var iterator = key.values(in: ubiquitousKeyValueStore, emitsInitialValue: false).makeAsyncIterator()

        NotificationCenter.default.post(
            name: NSUbiquitousKeyValueStore.didChangeInternallyNotification,
            object: ubiquitousKeyValueStore,
            userInfo: nil
        )

        NotificationCenter.default.post(
            name: NSUbiquitousKeyValueStore.didChangeInternallyNotification,
            object: ubiquitousKeyValueStore,
            userInfo: [
                NSUbiquitousKeyValueStoreChangedKeysKey: "notAnArray",
            ]
        )

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

        await fulfillment(of: [initialValueReceived])

        task.cancel()

        await fulfillment(of: [taskCompleted])
        await task.value

        XCTAssertEqual(store.deregistrationCount, 1)
    }
}

// MARK: - Test Utilities

extension PersistentKeyValuesTests {
    private func assertSendableAsyncSequence<Sequence>(
        _ sequence: Sequence
    ) where Sequence: AsyncSequence & Sendable, Sequence.Element: Sendable {}

    private func makeUserDefaults() throws -> (userDefaults: UserDefaults, suiteName: String) {
        let suiteName = "PersistentKeyValuesTests.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))

        userDefaults.removePersistentDomain(forName: suiteName)

        return (userDefaults, suiteName)
    }
}
