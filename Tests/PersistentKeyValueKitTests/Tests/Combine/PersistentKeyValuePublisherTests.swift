//
//  PersistentKeyValuePublisherTests.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 5/2/26.
//

import Combine
import Foundation
import PersistentKeyValueKit
import XCTest

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
    func test_publisher_ubiquitousKeyValueStoreIgnoresMalformedAndUnrelatedNotifications() {
        let ubiquitousKeyValueStore: NSUbiquitousKeyValueStore = MockUbiquitousKeyValueStore()
        let key = PersistentKey("key:\(#function)", defaultValue: "defaultValue")

        let values = receivedValues(from: key.publisher(in: ubiquitousKeyValueStore, emitsInitialValue: false)) {
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
        }

        XCTAssertEqual(values, ["changedValue"])
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
    private func makeUserDefaults() throws -> (userDefaults: UserDefaults, suiteName: String) {
        let suiteName = "PersistentKeyValuePublisherTests.\(UUID().uuidString)"
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

// MARK: - Reentrant Subscriber Definition

private final class ReentrantSubscriber<Input> where Input: Sendable {
    var onFirstReceive: (() -> Void)?

    private(set) var maximumReceiveDepth = 0
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
    private var capturedObserver: NSObject?
    private var deregistrations = 0
    private var storage: [String: Any] = [:]

    private(set) var getCount = 0

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
