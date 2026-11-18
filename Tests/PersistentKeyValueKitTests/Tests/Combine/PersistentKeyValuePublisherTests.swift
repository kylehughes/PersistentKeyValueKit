//
//  PersistentKeyValuePublisherTests.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 5/2/26.
//

import Combine
import Foundation
import XCTest

@testable import PersistentKeyValueKit

final class PersistentKeyValuePublisherTests: XCTestCase {
    private var cancellables: Set<AnyCancellable> = []

    override func tearDown() {
        cancellables.removeAll()

        super.tearDown()
    }
}

// MARK: - Initialization Tests

extension PersistentKeyValuePublisherTests {
    func test_init_emitsInitialValueCanBeFalse() {
        let key = PersistentKey("key:\(#function)", defaultValue: "defaultValue")

        let publisher = PersistentKeyValuePublisher(
            key,
            store: ObservablePersistentKeyValueStore(),
            emitsInitialValue: false
        )

        XCTAssertFalse(publisher.emitsInitialValue)
    }

    func test_init_emitsInitialValueDefaultsToTrue() {
        let key = PersistentKey("key:\(#function)", defaultValue: "defaultValue")

        let publisher = PersistentKeyValuePublisher(key, store: ObservablePersistentKeyValueStore())

        XCTAssertTrue(publisher.emitsInitialValue)
    }

    func test_init_storesKey() {
        let key = PersistentKey("key:\(#function)", defaultValue: "defaultValue")

        let publisher = PersistentKeyValuePublisher(key, store: ObservablePersistentKeyValueStore())

        XCTAssertEqual(publisher.key.id, key.id)
        XCTAssertEqual(publisher.key.defaultValue, key.defaultValue)
    }
}

// MARK: - Publisher Tests

extension PersistentKeyValuePublisherTests {
    func test_changes_keyConvenienceSkipsInitialValue() {
        let store = ObservablePersistentKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: "defaultValue")

        let values = receivedValues(from: key.changesPublisher(in: store)) {
            store.set(key, to: "changedValue")
        }

        XCTAssertEqual(values, ["changedValue"])
    }

    func test_changes_storeConvenienceSkipsInitialValue() {
        let store = ObservablePersistentKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: "defaultValue")

        let values = receivedValues(from: store.changesPublisher(for: key)) {
            store.set(key, to: "changedValue")
        }

        XCTAssertEqual(values, ["changedValue"])
    }

    func test_publisher_canSkipInitialValue() {
        let store = ObservablePersistentKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: "defaultValue")

        let values = receivedValues(from: key.publisher(in: store, emitsInitialValue: false)) {
            store.set(key, to: "changedValue")
        }

        XCTAssertEqual(values, ["changedValue"])
    }

    func test_publisher_changeOnAnotherThreadDuringSubscriptionIsDeliveredAfterSubscriptionReturns() {
        let store = InMemoryPersistentKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: 0)
        let subscriber = SubscriptionHookSubscriber<Int>()
        var valuesAfterRequest: [Int] = []
        var valuesAfterWrite: [Int] = []
        var writeResult: DispatchTimeoutResult?

        subscriber.onReceiveSubscription = { subscription in
            subscription.request(.unlimited)
            valuesAfterRequest = subscriber.values

            let written = DispatchSemaphore(value: 0)

            Thread.detachNewThread {
                store.set(key, to: 1)
                written.signal()
            }

            // The write does not wait for its change to be delivered, so this wait cannot deadlock.
            writeResult = written.wait(timeout: .now() + 5)
            valuesAfterWrite = subscriber.values
        }

        key.publisher(in: store).subscribe(subscriber)

        XCTAssertEqual(writeResult, .success)
        XCTAssertEqual(valuesAfterRequest, [0])
        XCTAssertEqual(valuesAfterWrite, [0])
        XCTAssertEqual(subscriber.values, [0, 1])
        XCTAssertTrue(subscriber.receivedEveryValueOnSubscribingThread)

        store.set(key, to: 2)

        XCTAssertEqual(subscriber.values, [0, 1, 2])

        subscriber.cancel()
    }

    func test_publisher_changeQueuedDuringSubscriptionIsDeliveredBySubscribingThreadDespiteCompetingDemand() {
        let store = InMemoryPersistentKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: 0)
        let subscriber = SubscriptionHookSubscriber<Int>()
        let subscriptionBox = SubscriptionBox()
        var competingRequestResult: DispatchTimeoutResult?
        var handoffWasObserved = false
        var valuesAfterCompetingRequest: [Int]?
        var writeResult: DispatchTimeoutResult?

        subscriber.onReceiveSubscription = { subscription in
            let handoff = subscription as? any PersistentKeyValueSubscriptionHandoffObserving

            subscriptionBox.subscription = subscription
            // Another thread requests demand after subscription ends but before the subscribing thread delivers the
            // change queued while it subscribed.
            handoff?.didFinishSubscribing = {
                let requested = DispatchSemaphore(value: 0)

                Thread.detachNewThread {
                    subscriptionBox.subscription?.request(.max(1))
                    requested.signal()
                }

                // The competing request does not wait for delivery, so this wait cannot deadlock.
                competingRequestResult = requested.wait(timeout: .now() + 5)
                valuesAfterCompetingRequest = subscriber.values
            }
            handoffWasObserved = handoff != nil
            subscription.request(.unlimited)

            let written = DispatchSemaphore(value: 0)

            Thread.detachNewThread {
                store.set(key, to: 1)
                written.signal()
            }

            writeResult = written.wait(timeout: .now() + 5)
        }

        key.changesPublisher(in: store).subscribe(subscriber)

        XCTAssertTrue(handoffWasObserved)
        XCTAssertEqual(writeResult, .success)
        XCTAssertEqual(competingRequestResult, .success)
        XCTAssertEqual(valuesAfterCompetingRequest, [])
        XCTAssertEqual(subscriber.values, [1])
        XCTAssertTrue(subscriber.receivedEveryValueOnSubscribingThread)

        subscriber.cancel()
    }

    func test_publisher_changeQueuedDuringSubscriptionIsDeliveredBySubscribingThreadUnderContention() {
        let deadline = Date(timeIntervalSinceNow: 0.5)
        var otherThreadDeliveries = 0
        var subscriptions = 0
        var timedOut = false

        // Each subscription queues a change from another thread while it subscribes, and that thread then requests
        // demand repeatedly until the change is delivered, racing the subscribing thread's delivery after it returns.
        while Date() < deadline, !timedOut {
            let store = InMemoryPersistentKeyValueStore()
            let key = PersistentKey("key:\(#function)", defaultValue: 0)
            let subscriber = SubscriptionHookSubscriber<Int>()
            let subscriptionBox = SubscriptionBox()
            let finished = DispatchSemaphore(value: 0)

            subscriber.onReceiveSubscription = { subscription in
                let written = DispatchSemaphore(value: 0)

                subscriptionBox.subscription = subscription
                subscription.request(.unlimited)
                DispatchQueue.global().async {
                    store.set(key, to: 1)
                    written.signal()

                    let requestDeadline = Date(timeIntervalSinceNow: 5)

                    while subscriber.values.isEmpty, Date() < requestDeadline {
                        subscriptionBox.subscription?.request(.max(1))
                    }

                    finished.signal()
                }

                if written.wait(timeout: .now() + 5) == .timedOut {
                    timedOut = true
                }
            }

            key.changesPublisher(in: store).subscribe(subscriber)

            if finished.wait(timeout: .now() + 5) == .timedOut {
                timedOut = true
            }

            if !subscriber.receivedEveryValueOnSubscribingThread {
                otherThreadDeliveries += 1
            }

            XCTAssertEqual(subscriber.values, [1])

            subscriber.cancel()
            subscriptions += 1
        }

        XCTAssertFalse(timedOut)
        XCTAssertGreaterThan(subscriptions, 0)
        XCTAssertEqual(otherThreadDeliveries, 0, "\(otherThreadDeliveries) of \(subscriptions) subscriptions")
    }

    func test_publisher_coalescesChangesUntilDemandIsRequested() {
        let store = ObservablePersistentKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: "defaultValue")
        let subscriber = DemandControlledSubscriber<String>()

        key.publisher(in: store, emitsInitialValue: false).subscribe(subscriber)

        store.set(key, to: "firstChangedValue")
        store.set(key, to: "secondChangedValue")

        XCTAssertEqual(subscriber.values, [])

        subscriber.request(.max(1))

        XCTAssertEqual(subscriber.values, ["secondChangedValue"])
    }

    func test_publisher_demandRequestedAgainDuringSubscriptionDeliversChangeQueuedOnAnotherThread() {
        let store = InMemoryPersistentKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: 0)
        let subscriber = SubscriptionHookSubscriber<Int>()
        var valuesAfterSecondRequest: [Int]?
        var valuesAfterWrite: [Int]?
        var writeResult: DispatchTimeoutResult?

        subscriber.onReceiveSubscription = { subscription in
            subscription.request(.unlimited)

            let written = DispatchSemaphore(value: 0)

            Thread.detachNewThread {
                store.set(key, to: 1)
                written.signal()
            }

            writeResult = written.wait(timeout: .now() + 5)
            valuesAfterWrite = subscriber.values
            // Demand requested on the subscribing thread is met before `receive(subscription:)` returns, including
            // with the change that the other thread queued.
            subscription.request(.max(1))
            valuesAfterSecondRequest = subscriber.values
        }

        key.changesPublisher(in: store).subscribe(subscriber)

        XCTAssertEqual(writeResult, .success)
        XCTAssertEqual(valuesAfterWrite, [])
        XCTAssertEqual(valuesAfterSecondRequest, [1])
        XCTAssertEqual(subscriber.values, [1])
        XCTAssertTrue(subscriber.receivedEveryValueOnSubscribingThread)

        store.set(key, to: 2)

        XCTAssertEqual(subscriber.values, [1, 2])

        subscriber.cancel()
    }

    func test_publisher_demandRequestedOnAnotherThreadDuringSubscriptionIsDeliveredAfterSubscriptionReturns() {
        let store = InMemoryPersistentKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: 0)
        let subscriber = SubscriptionHookSubscriber<Int>()
        let subscriptionBox = SubscriptionBox()
        var valuesAfterRequest: [Int]?
        var requestResult: DispatchTimeoutResult?

        subscriber.onReceiveSubscription = { subscription in
            let requested = DispatchSemaphore(value: 0)

            subscriptionBox.subscription = subscription
            Thread.detachNewThread {
                subscriptionBox.subscription?.request(.unlimited)
                requested.signal()
            }

            requestResult = requested.wait(timeout: .now() + 5)
            valuesAfterRequest = subscriber.values
        }

        key.publisher(in: store).subscribe(subscriber)

        XCTAssertEqual(requestResult, .success)
        XCTAssertEqual(valuesAfterRequest, [])
        XCTAssertEqual(subscriber.values, [0])
        XCTAssertTrue(subscriber.receivedEveryValueOnSubscribingThread)

        subscriber.cancel()
    }

    func test_publisher_emitsDefaultValueInitially() {
        let store = ObservablePersistentKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: "defaultValue")

        let values = receivedValues(from: key.publisher(in: store))

        XCTAssertEqual(values, ["defaultValue"])
    }

    func test_publisher_emitsEveryChangeWhileDemandIsAvailable() {
        let store = ObservablePersistentKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: "defaultValue")
        let subscriber = DemandControlledSubscriber<String>()

        key.publisher(in: store).subscribe(subscriber)

        subscriber.request(.max(3))
        store.set(key, to: "firstChangedValue")
        store.set(key, to: "secondChangedValue")

        XCTAssertEqual(subscriber.values, ["defaultValue", "firstChangedValue", "secondChangedValue"])
    }

    func test_publisher_emitsNilInitialValueForOptionalKey() {
        let store = ObservablePersistentKeyValueStore()
        let key = PersistentKey<String?>("key:\(#function)", defaultValue: nil)

        let values = receivedValues(from: key.publisher(in: store))

        XCTAssertEqual(values, [nil])
    }

    func test_publisher_emitsStoredValueInitially() {
        let store = ObservablePersistentKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: "defaultValue")

        store.set(key, to: "storedValue")

        let values = receivedValues(from: key.publisher(in: store))

        XCTAssertEqual(values, ["storedValue"])
    }

    func test_publisher_ignoresNotificationsForUnrelatedKeys() {
        let store = ObservablePersistentKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: "defaultValue")

        let values = receivedValues(from: key.changesPublisher(in: store)) {
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

    func test_publisher_ignoresUnrelatedKeyPathCallbacks() {
        let store = ObservablePersistentKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: "defaultValue")
        let unrelatedKey = PersistentKey("unrelatedKey:\(#function)", defaultValue: "unrelatedDefaultValue")

        let values = receivedValues(from: key.publisher(in: store, emitsInitialValue: false)) {
            store.notifyObservers(keyPath: unrelatedKey.id)
            store.set(key, to: "changedValue")
        }

        XCTAssertEqual(values, ["changedValue"])
    }

    func test_publisher_preservesInitialValueBeforeCoalescedChanges() {
        let store = ObservablePersistentKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: "defaultValue")
        let subscriber = DemandControlledSubscriber<String>()

        key.publisher(in: store).subscribe(subscriber)

        store.set(key, to: "firstChangedValue")
        store.set(key, to: "secondChangedValue")

        subscriber.request(.max(1))

        XCTAssertEqual(subscriber.values, ["defaultValue"])

        subscriber.request(.max(1))

        XCTAssertEqual(subscriber.values, ["defaultValue", "secondChangedValue"])
    }

    func test_publisher_reentrantDemandAndChangeDoNotNestEmissions() {
        let store = ObservablePersistentKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: "defaultValue")
        let subscriber = ReentrantSubscriber<String>()

        subscriber.onFirstReceive = {
            store.set(key, to: "reentrantValue")
            subscriber.request(.max(1))
        }

        key.publisher(in: store).subscribe(subscriber)

        subscriber.request(.max(1))

        XCTAssertEqual(subscriber.values, ["defaultValue", "reentrantValue"])
        XCTAssertEqual(subscriber.maximumReceiveDepth, 1)

        subscriber.request(.max(1))
        store.set(key, to: "laterValue")

        XCTAssertEqual(subscriber.values, ["defaultValue", "reentrantValue", "laterValue"])
        XCTAssertEqual(subscriber.maximumReceiveDepth, 1)

        subscriber.cancel()
    }

    func test_publisher_storeConvenienceEmitsInitialValue() {
        let store = ObservablePersistentKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: "defaultValue")

        let values = receivedValues(from: store.publisher(for: key))

        XCTAssertEqual(values, ["defaultValue"])
    }

    func test_publisher_unlimitedDemandEmitsEveryObservedChange() {
        let store = ObservablePersistentKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: "defaultValue")
        let subscriber = DemandControlledSubscriber<String>()

        key.publisher(in: store, emitsInitialValue: false).subscribe(subscriber)

        subscriber.request(.unlimited)
        store.set(key, to: "firstChangedValue")
        store.set(key, to: "secondChangedValue")

        XCTAssertEqual(subscriber.values, ["firstChangedValue", "secondChangedValue"])
    }

    func test_publisher_usesAdditionalDemandReturnedBySubscriber() {
        let store = ObservablePersistentKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: "defaultValue")
        let subscriber = DemandControlledSubscriber<String> { _ in
            .max(1)
        }

        key.publisher(in: store).subscribe(subscriber)

        subscriber.request(.max(1))
        store.set(key, to: "changedValue")

        XCTAssertEqual(subscriber.values, ["defaultValue", "changedValue"])
    }
}

// MARK: - Store Integration Tests

extension PersistentKeyValuePublisherTests {
    func test_publisher_inMemoryStoreEmitsDefaultValueAfterRemove() {
        let store = InMemoryPersistentKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: "defaultValue")

        store.set(key, to: "storedValue")

        let values = receivedValues(from: key.changesPublisher(in: store)) {
            store.remove(key)
        }

        XCTAssertEqual(values, ["defaultValue"])
    }

    func test_publisher_inMemoryStoreObservesChanges() {
        let store = InMemoryPersistentKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: "defaultValue")

        let values = receivedValues(from: key.changesPublisher(in: store)) {
            store.set(key, to: "changedValue")
        }

        XCTAssertEqual(values, ["changedValue"])
    }

    func test_publisher_inMemoryStoreOnlyEmitsInitialValue() {
        let store = InMemoryPersistentKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: "defaultValue")

        let values = receivedValues(from: key.publisher(in: store))

        XCTAssertEqual(values, ["defaultValue"])
    }

    @available(watchOS 9.0, *)
    func test_publisher_ubiquitousKeyValueStoreIgnoresUnrelatedNotifications() {
        let ubiquitousKeyValueStore: NSUbiquitousKeyValueStore = MockUbiquitousKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: "defaultValue")

        let values = receivedValues(from: key.publisher(in: ubiquitousKeyValueStore, emitsInitialValue: false)) {
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
        }

        XCTAssertEqual(values, ["changedValue"])
    }

    @available(watchOS 9.0, *)
    func test_publisher_ubiquitousKeyValueStoreRefreshesForAccountChange() {
        let ubiquitousKeyValueStore = MockUbiquitousKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: "defaultValue")

        let values = receivedValues(from: key.publisher(in: ubiquitousKeyValueStore, emitsInitialValue: false)) {
            ubiquitousKeyValueStore.storage[key.id] = "accountValue"
            NotificationCenter.default.post(
                name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                object: ubiquitousKeyValueStore,
                userInfo: [
                    NSUbiquitousKeyValueStoreChangeReasonKey: NSUbiquitousKeyValueStoreAccountChange,
                ]
            )
        }

        XCTAssertEqual(values, ["accountValue"])
    }

    @available(watchOS 9.0, *)
    func test_publisher_ubiquitousKeyValueStoreRefreshesWithoutChangedKeys() {
        let ubiquitousKeyValueStore = MockUbiquitousKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: "defaultValue")
        let publisher = key.publisher(in: ubiquitousKeyValueStore, emitsInitialValue: false)

        let values = receivedValues(from: publisher, expectedCount: 2) {
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
    func test_publisher_ubiquitousKeyValueStoreObservesChanges() {
        let ubiquitousKeyValueStore: NSUbiquitousKeyValueStore = MockUbiquitousKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: "defaultValue")

        let values = receivedValues(from: key.publisher(in: ubiquitousKeyValueStore, emitsInitialValue: false)) {
            ubiquitousKeyValueStore.set("changedValue", forKey: key.id)
        }

        XCTAssertEqual(values, ["changedValue"])
    }

    func test_publisher_userDefaultsObservesChanges() throws {
        let (userDefaults, suiteName) = try makeUserDefaults()
        let key = PersistentKey("key:\(#function)", defaultValue: "defaultValue")
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        let values = receivedValues(from: key.publisher(in: userDefaults, emitsInitialValue: false)) {
            userDefaults.set("changedValue", forKey: key.id)
        }

        XCTAssertEqual(values, ["changedValue"])
    }

    func test_publisher_readThatWritesObservedKeyDoesNotDeadlock() {
        let store = WritingOnReadPersistentKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: 0)
        let recorder = ValueRecorder<Int>()
        let finished = DispatchSemaphore(value: 0)

        // Model a representation that canonicalizes a legacy value by writing the observed key while decoding it. The
        // write reports a change synchronously, from inside the subscription's read.
        store.onRead = { [unowned store] in
            if store.base.get(key) == 1 {
                store.base.set(key, to: 2)
            }
        }

        // A deadlock blocks this thread forever, so run the write elsewhere and bound the wait. The store is private
        // to this test, so a deadlock cannot block other tests.
        Thread.detachNewThread {
            let cancellable = key.changesPublisher(in: store).sink { value in
                recorder.append(value)
            }

            store.set(key, to: 1)
            cancellable.cancel()
            finished.signal()
        }

        XCTAssertEqual(finished.wait(timeout: .now() + 5), .success, "The subscription deadlocked.")
        // The first read observes the canonicalized value; the change it reported is delivered as a later read.
        XCTAssertEqual(recorder.values, [2, 2])
    }

    func test_publisher_userDefaultsObservesKeyWithPeriods() throws {
        let (userDefaults, suiteName) = try makeUserDefaults()
        let key = PersistentKey("com.example.key.\(#function)", defaultValue: false)
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        let values = receivedValues(from: key.publisher(in: userDefaults), expectedCount: 3) {
            userDefaults.set(key, to: true)
            userDefaults.remove(key)
        }

        XCTAssertEqual(values, [false, true, false])
    }

    func test_publisher_userDefaultsObservesKeyPathIncompatibleKeys() throws {
        let (userDefaults, suiteName) = try makeUserDefaults()
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        for keyID in keyPathIncompatibleKeyIDs() {
            let key = PersistentKey(keyID, defaultValue: false)

            let values = receivedValues(from: key.publisher(in: userDefaults), expectedCount: 3) {
                userDefaults.set(key, to: true)
                userDefaults.remove(key)
            }

            XCTAssertEqual(values, [false, true, false], "\(keyID.unicodeScalars.map(\.value))")
        }
    }
}

// MARK: - Lifecycle Tests

extension PersistentKeyValuePublisherTests {
    func test_publisher_cancellationDeregisters() {
        let store = ObservablePersistentKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: "defaultValue")
        let cancellable = key.publisher(in: store).sink { _ in }

        XCTAssertEqual(store.registrationCount, 1)

        cancellable.cancel()

        XCTAssertEqual(store.deregistrationCount, 1)
    }

    func test_publisher_cancellationDeregistersOnce() {
        let store = ObservablePersistentKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: "defaultValue")
        let subscriber = DemandControlledSubscriber<String>()

        key.publisher(in: store).subscribe(subscriber)

        XCTAssertEqual(store.registrationCount, 1)

        subscriber.cancel()
        subscriber.cancel()

        XCTAssertEqual(store.deregistrationCount, 1)
    }

    func test_publisher_cancelledSubscriptionDoesNotEmitLaterChanges() {
        let store = ObservablePersistentKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: "defaultValue")
        let subscriber = DemandControlledSubscriber<String>()

        key.publisher(in: store, emitsInitialValue: false).subscribe(subscriber)

        XCTAssertEqual(store.registrationCount, 1)

        subscriber.request(.unlimited)
        subscriber.cancel()
        store.set(key, to: "changedValue")

        XCTAssertEqual(subscriber.values, [])
        XCTAssertEqual(store.deregistrationCount, 1)
    }

    func test_publisher_concurrentCancellationAndChangeDeregistersOnce() async {
        for iteration in 0 ..< 100 {
            let store = ObservablePersistentKeyValueStore()
            let key = PersistentKey("key:\(#function):\(iteration)", defaultValue: "defaultValue")
            let registered = expectation(description: "Subscription registered \(iteration)")
            let subscriber = DemandControlledSubscriber<String>()

            store.onNextRegistration {
                registered.fulfill()
            }

            key.publisher(in: store, emitsInitialValue: false).subscribe(subscriber)

            await fulfillment(of: [registered], timeout: 1)

            subscriber.request(.unlimited)

            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    subscriber.cancel()
                }

                group.addTask {
                    store.set(key, to: "changedValue")
                }
            }

            let values = subscriber.values

            XCTAssertTrue(values.isEmpty || values == ["changedValue"])
            XCTAssertEqual(store.deregistrationCount, 1)
        }
    }

    func test_publisher_cancellationReleasingSubscriberThatCancelsInDeinitDoesNotDeadlock() {
        let store = InMemoryPersistentKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: 0)
        let finished = DispatchSemaphore(value: 0)
        let subscriptionBox = SubscriptionBox()

        // A deadlock blocks this thread forever, so cancel elsewhere and bound the wait. The store is private to this
        // test, so a deadlock cannot block other tests.
        Thread.detachNewThread {
            key.publisher(in: store).subscribe(CancellingOnDeinitSubscriber<Int>(subscriptionBox: subscriptionBox))
            subscriptionBox.subscription?.cancel()
            finished.signal()
        }

        XCTAssertEqual(finished.wait(timeout: .now() + 5), .success, "Cancellation deadlocked.")
        XCTAssertTrue(subscriptionBox.didCancelInDeinit)
    }

    @available(watchOS 9.0, *)
    func test_publisher_decoderCancellingSubscriptionPreventsDelivery() {
        let subscriber = DemandControlledSubscriber<Int>()
        // The in-memory store does not decode values, so use a store that does.
        let store: NSUbiquitousKeyValueStore = MockUbiquitousKeyValueStore()
        let key = PersistentKey(
            "key:\(#function)",
            defaultValue: 0,
            representation: ProxyPersistentKeyValueRepresentation<Int, Int>(
                to: { $0 },
                from: { value in
                    if value == 6 {
                        subscriber.cancel()
                    }

                    return value
                }
            )
        )

        key.publisher(in: store, emitsInitialValue: false).subscribe(subscriber)
        subscriber.request(.unlimited)

        store.set(key, to: 5)
        store.set(key, to: 6)
        store.set(key, to: 7)

        // The mock reports each write twice, so `5` can be delivered more than once.
        XCTAssertEqual(Set(subscriber.values), [5])
    }

    func test_publisher_ignoresCallbackCapturedBeforeCancellation() {
        let store = CallbackRetainingPersistentKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: "defaultValue")
        let subscriber = DemandControlledSubscriber<String>()

        key.publisher(in: store, emitsInitialValue: false).subscribe(subscriber)

        XCTAssertTrue(store.hasCapturedObserver)

        subscriber.request(.unlimited)
        subscriber.cancel()
        store.notifyCapturedObserver(for: key.id)

        XCTAssertEqual(subscriber.values, [])
        XCTAssertEqual(store.deregistrationCount, 1)
        XCTAssertEqual(store.getCount, 0)
    }

    func test_publisher_ignoresDemandRequestedAfterCancellation() {
        let store = ObservablePersistentKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: "defaultValue")
        let subscriber = DemandControlledSubscriber<String>()

        key.publisher(in: store, emitsInitialValue: false).subscribe(subscriber)

        subscriber.cancel()
        subscriber.request(.unlimited)
        store.set(key, to: "changedValue")

        XCTAssertEqual(subscriber.values, [])
        XCTAssertEqual(store.deregistrationCount, 1)
    }

    func test_publisher_ignoresZeroDemandUntilPositiveDemandIsRequested() {
        let store = ObservablePersistentKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: "defaultValue")
        let subscriber = DemandControlledSubscriber<String>()

        key.publisher(in: store, emitsInitialValue: false).subscribe(subscriber)

        subscriber.request(.none)
        store.set(key, to: "changedValue")

        XCTAssertEqual(subscriber.values, [])

        subscriber.request(.max(1))

        XCTAssertEqual(subscriber.values, ["changedValue"])
    }

    func test_publisher_releasingCancellableDeregisters() {
        let store = ObservablePersistentKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: "defaultValue")
        var cancellable: AnyCancellable? = key.publisher(in: store).sink { _ in }

        XCTAssertNotNil(cancellable)
        XCTAssertEqual(store.registrationCount, 1)

        cancellable = nil

        XCTAssertEqual(store.deregistrationCount, 1)
    }

    func test_publisher_subscribersRegisterIndependently() {
        let store = ObservablePersistentKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: "defaultValue")
        let firstCancellable = key.publisher(in: store).sink { _ in }
        let secondCancellable = key.publisher(in: store).sink { _ in }

        XCTAssertEqual(store.registrationCount, 2)

        firstCancellable.cancel()

        XCTAssertEqual(store.deregistrationCount, 1)

        secondCancellable.cancel()

        XCTAssertEqual(store.deregistrationCount, 2)
    }
}

// MARK: - Test Utilities

extension PersistentKeyValuePublisherTests {
    private func makeUserDefaults(_ function: String = #function) throws -> (userDefaults: UserDefaults, suiteName: String) {
        let suiteName = stableSuiteName("PersistentKeyValuePublisherTests", function: function)
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))

        userDefaults.removePersistentDomain(forName: suiteName)

        return (userDefaults, suiteName)
    }

    private func receivedValues<P>(
        from publisher: P,
        expectedCount: Int = 1,
        after action: () -> Void = {}
    ) -> [P.Output] where P: Publisher, P.Failure == Never {
        var values: [P.Output] = []
        let valuesEmitted = expectation(description: "Values emitted")
        valuesEmitted.expectedFulfillmentCount = expectedCount

        publisher.sink { value in
            values.append(value)
            valuesEmitted.fulfill()
        }.store(in: &cancellables)

        action()

        wait(for: [valuesEmitted], timeout: 1)

        return values
    }
}

private final class DemandControlledSubscriber<Input>: Subscriber, @unchecked Sendable where Input: Sendable {
    typealias Failure = Never

    private let demandAfterReceive: @Sendable (Input) -> Subscribers.Demand
    private let lock: NSLock
    private var receivedValues: [Input]
    private var subscription: Subscription?

    init(demandAfterReceive: @escaping @Sendable (Input) -> Subscribers.Demand = { _ in .none }) {
        self.demandAfterReceive = demandAfterReceive
        lock = NSLock()
        receivedValues = []
        subscription = nil
    }

    var values: [Input] {
        withLock {
            receivedValues
        }
    }

    func cancel() {
        let subscription = withLock {
            self.subscription
        }

        subscription?.cancel()
    }

    func receive(_ input: Input) -> Subscribers.Demand {
        withLock {
            receivedValues.append(input)
        }

        return demandAfterReceive(input)
    }

    func receive(completion: Subscribers.Completion<Never>) {
    }

    func receive(subscription: Subscription) {
        withLock {
            self.subscription = subscription
        }
    }

    func request(_ demand: Subscribers.Demand) {
        let subscription = withLock {
            self.subscription
        }

        subscription?.request(demand)
    }

    private func withLock<Result>(_ body: () -> Result) -> Result {
        lock.lock()
        defer {
            lock.unlock()
        }

        return body()
    }
}

// MARK: - Subscription Box Definition

/// Holds a subscription strongly for a subscriber that cancels it from `deinit`.
private final class SubscriptionBox: @unchecked Sendable {
    var didCancelInDeinit = false
    var subscription: Subscription?
}

// MARK: - Cancelling On Deinit Subscriber Definition

/// A subscriber that cancels its subscription when it is deinitialized, which happens when the subscription releases
/// it during cancellation.
private final class CancellingOnDeinitSubscriber<Input>: Subscriber {
    typealias Failure = Never

    private let subscriptionBox: SubscriptionBox

    init(subscriptionBox: SubscriptionBox) {
        self.subscriptionBox = subscriptionBox
    }

    deinit {
        subscriptionBox.subscription?.cancel()
        subscriptionBox.didCancelInDeinit = true
    }

    func receive(_ input: Input) -> Subscribers.Demand {
        .none
    }

    func receive(completion: Subscribers.Completion<Never>) {
    }

    func receive(subscription: Subscription) {
        subscriptionBox.subscription = subscription
    }
}

// MARK: - Writing On Read Persistent Key-Value Store Definition

/// A store that runs ``onRead`` before every read, so a read can write and report a change synchronously.
private final class WritingOnReadPersistentKeyValueStore: PersistentKeyValueStore, @unchecked Sendable {
    let base = InMemoryPersistentKeyValueStore()

    nonisolated(unsafe) var onRead: (() -> Void)?

    var migrationEndpoint: PersistentKeyValueMigrationEndpoint {
        base.migrationEndpoint
    }

    func deregister<Key>(
        _ observer: NSObject,
        for key: Key,
        context: UnsafeMutableRawPointer?
    ) where Key: PersistentKeyProtocol {
        base.deregister(observer, for: key, context: context)
    }

    func get<Key>(_ key: Key) -> Key.Value where Key: PersistentKeyProtocol {
        onRead?()

        return base.get(key)
    }

    func register<Key>(
        observer: NSObject,
        for key: Key,
        with context: UnsafeMutableRawPointer?,
        and selector: Selector
    ) where Key: PersistentKeyProtocol {
        base.register(observer: observer, for: key, with: context, and: selector)
    }

    func remove<Key>(_ key: Key) where Key: PersistentKeyProtocol {
        base.remove(key)
    }

    func set<Key>(_ key: Key, to value: Key.Value) where Key: PersistentKeyProtocol {
        base.set(key, to: value)
    }
}

// MARK: - Value Recorder Definition

/// Records values delivered on any thread.
private final class ValueRecorder<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedValues: [Value] = []

    var values: [Value] {
        lock.lock()
        defer {
            lock.unlock()
        }

        return recordedValues
    }

    func append(_ value: Value) {
        lock.lock()
        defer {
            lock.unlock()
        }

        recordedValues.append(value)
    }
}

// MARK: - Reentrant Subscriber Definition

private final class ReentrantSubscriber<Input> where Input: Sendable {
    private(set) var maximumReceiveDepth = 0
    var onFirstReceive: (() -> Void)?
    private(set) var values: [Input] = []

    private var receiveDepth = 0
    private var subscription: Subscription?

    // MARK: Internal Instance Interface

    func cancel() {
        let subscription = self.subscription
        self.subscription = nil
        subscription?.cancel()
    }

    func request(_ demand: Subscribers.Demand) {
        subscription?.request(demand)
    }
}

// MARK: - Subscriber Extension

extension ReentrantSubscriber: Subscriber {
    typealias Failure = Never

    func receive(_ input: Input) -> Subscribers.Demand {
        receiveDepth += 1
        maximumReceiveDepth = max(maximumReceiveDepth, receiveDepth)
        values.append(input)

        if values.count == 1 {
            let callback = onFirstReceive
            onFirstReceive = nil
            callback?()
        }

        receiveDepth -= 1

        return .none
    }

    func receive(completion: Subscribers.Completion<Never>) {
    }

    func receive(subscription: Subscription) {
        self.subscription = subscription
    }
}

// MARK: - Callback Retaining Persistent Key-Value Store Definition

private final class CallbackRetainingPersistentKeyValueStore {
    private(set) var getCount = 0

    private var capturedObserver: NSObject?
    private var deregistrations = 0
    private var storage: [String: Any] = [:]

    // MARK: Internal Instance Interface

    var deregistrationCount: Int {
        deregistrations
    }

    var hasCapturedObserver: Bool {
        capturedObserver != nil
    }

    func notifyCapturedObserver(for keyID: String) {
        let observer = capturedObserver
        capturedObserver = nil

        observer?.observeValue(
            forKeyPath: keyID,
            of: self,
            change: nil,
            context: nil
        )
    }
}

// MARK: - PersistentKeyValueStore Extension

extension CallbackRetainingPersistentKeyValueStore: PersistentKeyValueStore {
    var migrationEndpoint: PersistentKeyValueMigrationEndpoint {
        get throws {
            throw PersistentKeyMigrationError.missingMigrationDomain
        }
    }

    func deregister<Key>(
        _ observer: NSObject,
        for key: Key,
        context: UnsafeMutableRawPointer?
    ) where Key: PersistentKeyProtocol {
        deregistrations += 1
    }

    func get<Key>(_ key: Key) -> Key.Value where Key: PersistentKeyProtocol {
        getCount += 1

        return storage[key.id] as? Key.Value ?? key.defaultValue
    }

    func register<Key>(
        observer: NSObject,
        for key: Key,
        with context: UnsafeMutableRawPointer?,
        and selector: Selector
    ) where Key: PersistentKeyProtocol {
        capturedObserver = observer
    }

    func remove<Key>(_ key: Key) where Key: PersistentKeyProtocol {
        storage.removeValue(forKey: key.id)
    }

    func set<Key>(_ key: Key, to value: Key.Value) where Key: PersistentKeyProtocol {
        storage[key.id] = value
    }
}

// MARK: - Subscription Hook Subscriber Definition

/// A subscriber that runs ``onReceiveSubscription`` from `receive(subscription:)` and records the thread that delivers
/// each value.
private final class SubscriptionHookSubscriber<Input>: @unchecked Sendable {
    var onReceiveSubscription: ((Subscription) -> Void)?

    private let lock = NSLock()
    private var receivedValues: [Input] = []
    private var receivedOnOtherThread = false
    private var subscribingThread: pthread_t?
    private var subscription: Subscription?

    // MARK: Internal Instance Interface

    /// Whether every value was delivered on the thread that delivered the subscription.
    var receivedEveryValueOnSubscribingThread: Bool {
        withLock {
            !receivedOnOtherThread
        }
    }

    var values: [Input] {
        withLock {
            receivedValues
        }
    }

    func cancel() {
        let subscription = withLock {
            self.subscription
        }

        subscription?.cancel()
    }

    // MARK: Private Instance Interface

    private func withLock<Result>(_ body: () -> Result) -> Result {
        lock.lock()
        defer {
            lock.unlock()
        }

        return body()
    }
}

// MARK: - Subscriber Extension

extension SubscriptionHookSubscriber: Subscriber {
    typealias Failure = Never

    func receive(_ input: Input) -> Subscribers.Demand {
        withLock {
            receivedValues.append(input)

            if let subscribingThread, pthread_equal(subscribingThread, pthread_self()) == 0 {
                receivedOnOtherThread = true
            }
        }

        return .none
    }

    func receive(completion: Subscribers.Completion<Never>) {
    }

    func receive(subscription: Subscription) {
        withLock {
            subscribingThread = pthread_self()
            self.subscription = subscription
        }

        onReceiveSubscription?(subscription)
    }
}
