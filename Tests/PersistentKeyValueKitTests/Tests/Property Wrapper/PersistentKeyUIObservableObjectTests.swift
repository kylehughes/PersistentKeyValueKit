//
//  PersistentKeyUIObservableObjectTests.swift
//  PersistentKeyValueKit
//

import Combine
import Foundation
import PersistentKeyValueKit
import XCTest

final class PersistentKeyUIObservableObjectTests: XCTestCase {
    // MARK: Tests

    @MainActor
    func test_observer_deliversBackgroundCallbackOnMainActor() async {
        let store = ObservablePersistentKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: "defaultValue")
        let observer = PersistentKeyUIObservableObject(store: store, key: key)
        let callbackExpectation = expectation(description: "Change delivered on the main thread")
        let backgroundExpectation = expectation(description: "Background notification completed")
        var callbackOnMainThread = false
        let cancellable = observer.objectWillChange.sink {
            callbackOnMainThread = Thread.isMainThread
            callbackExpectation.fulfill()
        }

        DispatchQueue.global().async {
            store.notifyObservers(keyPath: key.id)
            backgroundExpectation.fulfill()
        }

        await fulfillment(of: [callbackExpectation, backgroundExpectation], timeout: 1)

        XCTAssertTrue(callbackOnMainThread)
        cancellable.cancel()
    }

    @available(watchOS 9.0, *)
    @MainActor
    func test_observer_ignoresUnrelatedCloudNotifications() {
        let store: NSUbiquitousKeyValueStore = MockUbiquitousKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: "defaultValue")
        let observer = PersistentKeyUIObservableObject(store: store, key: key)
        var changeCount = 0
        let cancellable = observer.objectWillChange.sink {
            changeCount += 1
        }

        let notificationName = NSUbiquitousKeyValueStore.didChangeInternallyNotification
        NotificationCenter.default.post(
            name: notificationName,
            object: store,
            userInfo: [
                NSUbiquitousKeyValueStoreChangedKeysKey: [
                    "unrelatedKey:\(#function)",
                ],
            ]
        )

        XCTAssertEqual(changeCount, 0)

        NotificationCenter.default.post(
            name: notificationName,
            object: store,
            userInfo: [
                NSUbiquitousKeyValueStoreChangedKeysKey: [key.id],
            ]
        )

        XCTAssertEqual(changeCount, 1)
        cancellable.cancel()
    }

    @available(watchOS 9.0, *)
    @MainActor
    func test_observer_refreshesForCloudAccountChangeAndMissingChangedKeys() {
        let store: NSUbiquitousKeyValueStore = MockUbiquitousKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: "defaultValue")
        let observer = PersistentKeyUIObservableObject(store: store, key: key)
        var changeCount = 0
        let cancellable = observer.objectWillChange.sink {
            changeCount += 1
        }

        let notificationName = NSUbiquitousKeyValueStore.didChangeExternallyNotification
        NotificationCenter.default.post(
            name: notificationName,
            object: store,
            userInfo: [
                NSUbiquitousKeyValueStoreChangeReasonKey: NSUbiquitousKeyValueStoreAccountChange,
                NSUbiquitousKeyValueStoreChangedKeysKey: [
                    "unrelatedKey:\(#function)",
                ],
            ]
        )
        NotificationCenter.default.post(name: notificationName, object: store, userInfo: nil)
        NotificationCenter.default.post(
            name: notificationName,
            object: store,
            userInfo: [NSUbiquitousKeyValueStoreChangedKeysKey: "notAnArray"]
        )

        XCTAssertEqual(changeCount, 3)
        cancellable.cancel()
    }

    @MainActor
    func test_observer_ignoresNotificationsForUnrelatedKeys() {
        let store = ObservablePersistentKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: "defaultValue")
        let observer = PersistentKeyUIObservableObject(store: store, key: key)
        var changeCount = 0
        let cancellable = observer.objectWillChange.sink {
            changeCount += 1
        }

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

        XCTAssertEqual(changeCount, 0)

        store.postToObservers(
            Notification(
                name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                object: store,
                userInfo: [
                    NSUbiquitousKeyValueStoreChangedKeysKey: [key.id],
                ]
            )
        )

        XCTAssertEqual(changeCount, 1)
        cancellable.cancel()
    }

    @MainActor
    func test_observer_ignoresUnrelatedKeyValueObservation() {
        let store = ObservablePersistentKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: "defaultValue")
        let observer = PersistentKeyUIObservableObject(store: store, key: key)
        var changeCount = 0
        let cancellable = observer.objectWillChange.sink {
            changeCount += 1
        }

        store.notifyObservers(keyPath: "unrelatedKey:\(#function)")

        XCTAssertEqual(changeCount, 0)

        store.notifyObservers(keyPath: key.id)

        XCTAssertEqual(changeCount, 1)
        cancellable.cancel()
    }

    @MainActor
    func test_store_returnsObservedStore() {
        let firstStore = ObservablePersistentKeyValueStore()
        let secondStore = ObservablePersistentKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: "defaultValue")
        let observer = PersistentKeyUIObservableObject(store: firstStore, key: key)

        XCTAssertTrue(observer.store as AnyObject === firstStore)

        observer.store = secondStore

        XCTAssertTrue(observer.store as AnyObject === secondStore)
        XCTAssertEqual(firstStore.deregistrationCount, 1)
        XCTAssertEqual(secondStore.registrationCount, 1)
    }

    @MainActor
    func test_value_set_writesStoreObservedBeforeChangeNotification() {
        let firstStore = InMemoryPersistentKeyValueStore()
        let secondStore = InMemoryPersistentKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: 0)
        let observer = PersistentKeyUIObservableObject(store: firstStore, key: key)
        var hasSwitchedStore = false

        // A synchronous subscriber switches the observed store while the write is being announced.
        let cancellable = observer.objectWillChange.sink {
            guard !hasSwitchedStore else {
                return
            }

            hasSwitchedStore = true
            observer.store = secondStore
        }

        observer.value = 42

        XCTAssertTrue(hasSwitchedStore)
        XCTAssertEqual(firstStore.get(key), 42)
        XCTAssertEqual(secondStore.get(key), 0)
        XCTAssertEqual(observer.value, 0)

        cancellable.cancel()
    }

    #if !DEBUG
    @MainActor
    func test_observer_withoutStore_usesDefaultAndDoesNotWrite() {
        let key = PersistentKey("key:\(#function)", defaultValue: "defaultValue")
        let observer = PersistentKeyUIObservableObject(store: nil, key: key)

        XCTAssertEqual(observer.value, "defaultValue")

        observer.value = "newValue"

        XCTAssertEqual(observer.value, "defaultValue")
    }
    #endif
}
