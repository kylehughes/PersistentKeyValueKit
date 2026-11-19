//
//  PersistentKeyUIObservableObjectTests.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 9/15/26.
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

        await fulfillment(of: [callbackExpectation, backgroundExpectation], timeout: 5)

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
    func test_store_set_deregistersStoreDeselectedDuringRegistration() {
        let deselectedStore = ObservablePersistentKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: 0)
        let observer = PersistentKeyUIObservableObject(store: InMemoryPersistentKeyValueStore(), key: key)

        // A synchronous subscriber clears the store while the registration is still being made.
        let cancellable = observer.objectWillChange.sink {
            observer.store = nil
        }

        deselectedStore.onNextRegistration {
            deselectedStore.notifyObservers(keyPath: key.id)
        }

        observer.store = deselectedStore

        XCTAssertNil(observer.store)
        XCTAssertEqual(deselectedStore.registrationCount, 1)
        XCTAssertEqual(deselectedStore.deregistrationCount, 1)

        cancellable.cancel()
    }

    @MainActor
    func test_store_set_notifiesAfterSelectingDifferentStore() {
        let firstStore = InMemoryPersistentKeyValueStore()
        let secondStore = InMemoryPersistentKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: 0)
        let observer = PersistentKeyUIObservableObject(store: firstStore, key: key)
        var notifiedValues: [Int] = []
        let cancellable = observer.objectWillChange.sink {
            notifiedValues.append(observer.value)
        }

        firstStore.set(key, to: 1)
        secondStore.set(key, to: 2)
        notifiedValues = []

        observer.store = secondStore

        XCTAssertEqual(notifiedValues, [2])

        observer.store = firstStore

        XCTAssertEqual(notifiedValues, [2, 1])

        cancellable.cancel()
    }

    @MainActor
    func test_store_set_dropsChangesQueuedByPreviousStore() {
        let previousStore = InMemoryPersistentKeyValueStore()
        let selectedStore = InMemoryPersistentKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: 0)
        let observer = PersistentKeyUIObservableObject(store: previousStore, key: key)
        let written = DispatchSemaphore(value: 0)

        // Background writes queue their change notifications on the main queue, which is busy until the switch.
        DispatchQueue.global().async {
            for value in 1...32 {
                previousStore.set(key, to: value)
            }

            written.signal()
        }

        let writesResult = written.wait(timeout: .now() + 5)
        XCTAssertEqual(writesResult, .success, "The background writes did not finish")

        guard writesResult == .success else {
            return
        }

        observer.store = selectedStore

        var notifiedValues: [Int] = []
        let cancellable = observer.objectWillChange.sink {
            notifiedValues.append(observer.value)
        }

        // The main queue runs blocks in order, so this runs after every queued notification.
        let drained = expectation(description: "Queued notifications ran")

        DispatchQueue.main.async {
            drained.fulfill()
        }

        wait(for: [drained], timeout: 5)

        XCTAssertEqual(notifiedValues, [])

        selectedStore.set(key, to: 9)

        XCTAssertEqual(notifiedValues, [9])

        cancellable.cancel()
    }

    @MainActor
    func test_store_set_doesNotNotifyForSameSelection() {
        let store = ObservablePersistentKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: 0)
        let observer = PersistentKeyUIObservableObject(store: store, key: key)
        let storelessObserver = PersistentKeyUIObservableObject(store: nil, key: key)
        var changeCount = 0
        let cancellables = [observer.objectWillChange, storelessObserver.objectWillChange].map {
            $0.sink { changeCount += 1 }
        }

        observer.store = store
        storelessObserver.store = nil

        XCTAssertEqual(changeCount, 0)
        XCTAssertEqual(store.registrationCount, 1)
        XCTAssertEqual(store.deregistrationCount, 0)

        store.notifyObservers(keyPath: key.id)

        XCTAssertEqual(changeCount, 1)

        cancellables.forEach { $0.cancel() }
    }

    @MainActor
    func test_store_set_nil_notifiesWithDefaultValue() {
        let store = InMemoryPersistentKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: 17)
        let observer = PersistentKeyUIObservableObject(store: store, key: key)
        var notifiedValues: [Int] = []
        let cancellable = observer.objectWillChange.sink {
            notifiedValues.append(observer.value)
        }

        store.set(key, to: 9)
        notifiedValues = []

        observer.store = nil

        XCTAssertNil(observer.store)
        XCTAssertEqual(notifiedValues, [17])
        XCTAssertEqual(observer.value, 17)

        store.set(key, to: 10)

        XCTAssertEqual(notifiedValues, [17])

        cancellable.cancel()
    }

    @MainActor
    func test_store_set_observesStoreSelectedWhilePreviousRegistrationIsRemoved() {
        let previousStore = ObservablePersistentKeyValueStore()
        let selectedStore = ObservablePersistentKeyValueStore()
        let finalStore = InMemoryPersistentKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: 0)
        let observer = PersistentKeyUIObservableObject(store: previousStore, key: key)
        var changeCount = 0
        let cancellable = observer.objectWillChange.sink {
            changeCount += 1
        }

        // Removing the previous registration selects another store before the selection that removed it returns.
        previousStore.onNextDeregistration {
            observer.store = finalStore
        }

        finalStore.set(key, to: 3)
        observer.store = selectedStore

        XCTAssertTrue(observer.store as AnyObject === finalStore)
        XCTAssertEqual(observer.value, 3)
        XCTAssertEqual(selectedStore.registrationCount, 1)
        XCTAssertEqual(selectedStore.deregistrationCount, 1)

        changeCount = 0
        selectedStore.notifyObservers(keyPath: key.id)

        XCTAssertEqual(changeCount, 0)

        finalStore.set(key, to: 4)

        XCTAssertEqual(changeCount, 1)

        cancellable.cancel()
    }

    @MainActor
    func test_store_set_observesStoreSelectedWhilePreviousStoreIsReleased() throws {
        let selectedStore = InMemoryPersistentKeyValueStore()
        let finalStore = InMemoryPersistentKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: 0)
        let observer = PersistentKeyUIObservableObject(store: InMemoryPersistentKeyValueStore(), key: key)
        var notifiedValues: [Int] = []
        let cancellable = observer.objectWillChange.sink {
            notifiedValues.append(observer.value)
        }

        selectedStore.set(key, to: 2)
        finalStore.set(key, to: 3)

        // The observer holds the only reference to its first store, whose release selects another store.
        do {
            let releasedStore = try XCTUnwrap(observer.store as? InMemoryPersistentKeyValueStore)

            releasedStore.set(
                ReleaseAction {
                    observer.store = finalStore
                },
                forKey: "releaseAction:\(#function)"
            )
        }

        observer.store = selectedStore

        XCTAssertTrue(observer.store as AnyObject === finalStore)
        XCTAssertEqual(observer.value, 3)
        XCTAssertEqual(notifiedValues, [3, 3])

        notifiedValues = []
        selectedStore.set(key, to: 4)

        XCTAssertEqual(notifiedValues, [])

        finalStore.set(key, to: 5)

        XCTAssertEqual(notifiedValues, [5])

        cancellable.cancel()
    }

    @MainActor
    func test_store_set_sameStore_observesConcurrentWrites() {
        let store = InMemoryPersistentKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: 0)
        let observer = PersistentKeyUIObservableObject(store: store, key: key)
        var notifiedValue = 0
        let cancellable = observer.objectWillChange.sink {
            notifiedValue = observer.value
        }
        var missedWrites = 0

        // Each write races repeated assignments of the store that is already selected.
        for value in 1...100 {
            let written = DispatchSemaphore(value: 0)

            DispatchQueue.global().async {
                store.set(key, to: value)
                written.signal()
            }

            for _ in 0..<40 {
                observer.store = store
            }

            let writeResult = written.wait(timeout: .now() + 5)
            XCTAssertEqual(writeResult, .success, "Write \(value) did not finish")

            guard writeResult == .success else {
                return
            }

            // A delivered change is already enqueued on the main queue when the write returns, so draining the main
            // queue once runs it.
            let drained = expectation(description: "Main queue drained after write \(value)")

            DispatchQueue.main.async {
                drained.fulfill()
            }

            wait(for: [drained], timeout: 5)

            if notifiedValue != value {
                missedWrites += 1
                break
            }
        }

        XCTAssertEqual(missedWrites, 0)

        cancellable.cancel()
    }

    @MainActor
    func test_store_set_valueTypeStore_observesChangeDuringReplacement() {
        let base = ObservablePersistentKeyValueStore()
        let store = ValueTypeStore(base: base)
        let key = PersistentKey("key:\(#function)", defaultValue: 0)
        let observer = PersistentKeyUIObservableObject(store: store, key: key)
        var notifiedValues: [Int] = []
        let cancellable = observer.objectWillChange.sink {
            notifiedValues.append(observer.value)
        }

        // A value-type store has no identity, so setting it again replaces the registration, and a write lands while
        // the previous registration is removed.
        base.onNextDeregistration {
            base.set(key, to: 4)
        }

        observer.store = store

        XCTAssertEqual(base.registrationCount, 2)
        XCTAssertEqual(base.deregistrationCount, 1)
        XCTAssertEqual(notifiedValues, [4, 4])

        base.set(key, to: 5)

        XCTAssertEqual(notifiedValues, [4, 4, 5])

        cancellable.cancel()
    }

    @MainActor
    func test_store_set_observesStoreSelectedDuringRegistration() throws {
        let suiteName = stableSuiteName("PersistentKeyUIObservableObjectTests", function: #function)
        let deselectedStore = try XCTUnwrap(InstrumentedUserDefaults(suiteName: suiteName))
        let selectedStore = InMemoryPersistentKeyValueStore()
        let key = PersistentKey("com.example.key.\(#function)", defaultValue: 0)
        let observer = PersistentKeyUIObservableObject(store: InMemoryPersistentKeyValueStore(), key: key)
        var changeCount = 0
        var hasSwitchedStore = false
        defer {
            deselectedStore.removePersistentDomain(forName: suiteName)
        }

        // A synchronous subscriber selects another store while the first registration is still being made.
        let cancellable = observer.objectWillChange.sink {
            changeCount += 1

            guard !hasSwitchedStore else {
                return
            }

            hasSwitchedStore = true
            observer.store = selectedStore
        }

        // A write made during the registration's first read notifies the observer before registration returns.
        deselectedStore.instrument(key.id)
        deselectedStore.afterNextRead {
            deselectedStore.set(1, forKey: key.id)
        }

        observer.store = deselectedStore

        XCTAssertTrue(hasSwitchedStore)
        XCTAssertTrue(observer.store as AnyObject === selectedStore)

        changeCount = 0
        selectedStore.set(key, to: 42)

        XCTAssertEqual(changeCount, 1)
        XCTAssertEqual(observer.value, 42)

        deselectedStore.set(key, to: 9)

        XCTAssertEqual(changeCount, 1)

        cancellable.cancel()
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

// MARK: - ReleaseAction Definition

/// An object that performs an action when it is released.
private final class ReleaseAction {
    private let action: @MainActor () -> Void

    // MARK: Internal Initialization

    init(_ action: @escaping @MainActor () -> Void) {
        self.action = action
    }

    // MARK: Deinitialization

    deinit {
        MainActor.assumeIsolated(action)
    }
}

// MARK: - ValueTypeStore Definition

/// A value-type store that forwards every operation to a backing store.
private struct ValueTypeStore: ForwardingPersistentKeyValueStore {
    let base: ObservablePersistentKeyValueStore
}
