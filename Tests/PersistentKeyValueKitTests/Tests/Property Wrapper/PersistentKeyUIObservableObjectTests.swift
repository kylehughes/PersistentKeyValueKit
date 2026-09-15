//
//  PersistentKeyUIObservableObjectTests.swift
//  PersistentKeyValueKit
//

import Combine
import Foundation
import PersistentKeyValueKit
import XCTest

final class PersistentKeyUIObservableObjectTests: XCTestCase {
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

    @available(watchOS 9.0, *)
    @MainActor
    func test_observer_ignoresMalformedAndUnrelatedCloudNotifications() {
        let store: NSUbiquitousKeyValueStore = MockUbiquitousKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: "defaultValue")
        let observer = PersistentKeyUIObservableObject(store: store, key: key)
        var changeCount = 0
        let cancellable = observer.objectWillChange.sink {
            changeCount += 1
        }

        let notificationName = NSUbiquitousKeyValueStore.didChangeInternallyNotification
        NotificationCenter.default.post(name: notificationName, object: store, userInfo: nil)
        NotificationCenter.default.post(
            name: notificationName,
            object: store,
            userInfo: [NSUbiquitousKeyValueStoreChangedKeysKey: "notAnArray"]
        )
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
