//
//  UserDefaultsKeyChangeObservationTests.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 11/17/26.
//

import Combine
import Foundation
import XCTest

@testable import PersistentKeyValueKit

/// Tests observation of `UserDefaults` keys whose identifiers contain a period, which key-value observation cannot
/// observe.
final class UserDefaultsKeyChangeObservationTests: XCTestCase {
    private var storage: InstrumentedUserDefaults!
    private var suiteName: String!

    // MARK: XCTestCase Implementation

    override func setUpWithError() throws {
        suiteName = stableSuiteName("UserDefaultsKeyChangeObservationTests", function: name)
        storage = try XCTUnwrap(InstrumentedUserDefaults(suiteName: suiteName))
    }

    override func tearDown() {
        storage.removePersistentDomain(forName: suiteName)
        storage = nil
        suiteName = nil
    }
}

// MARK: - Ordering Tests

extension UserDefaultsKeyChangeObservationTests {
    // MARK: Tests

    func test_register_deliversChangeMadeDuringFirstRead() {
        let observer = RecordingKeyObserver()
        let key = PersistentKey("com.example.key.\(#function)", defaultValue: 0)

        storage.instrument(key.id)
        storage.afterNextRead { [storage] in
            storage?.set(1, forKey: key.id)
        }

        storage.register(observer: observer, for: key, with: nil, and: #selector(RecordingKeyObserver.didReceive(_:)))

        XCTAssertEqual(storage.get(key), 1)
        XCTAssertEqual(observer.observations.count, 1)

        storage.deregister(observer, for: key, context: nil)
    }

    func test_publisher_staleReadDoesNotSuppressLaterChange() {
        let key = PersistentKey("com.example.key.\(#function)", defaultValue: 0)
        var values: [Int] = []

        storage.set(0, forKey: key.id)

        let cancellable = storage.publisher(for: key).sink { value in
            values.append(value)
        }

        // The change to `2` is reported while the change to `1` is still being read.
        storage.instrument(key.id)
        storage.afterNextRead { [storage] in
            storage?.set(2, forKey: key.id)
        }

        storage.set(1, forKey: key.id)

        XCTAssertEqual(storage.get(key), 2)
        XCTAssertEqual(values.last, 2)

        storage.set(1, forKey: key.id)

        XCTAssertEqual(storage.get(key), 1)
        XCTAssertEqual(values.last, 1)

        cancellable.cancel()
    }

    func test_register_callbackDuringRegistrationCanDeregister() {
        let key = PersistentKey("com.example.key.\(#function)", defaultValue: 0)
        let observer = DeregisteringKeyObserver(store: storage, key: key)

        // The change is made while registration reads the key's first comparison value.
        storage.instrument(key.id)
        storage.afterNextRead { [storage] in
            storage?.set(1, forKey: key.id)
        }

        storage.register(observer: observer, for: key, with: nil, and: #selector(DeregisteringKeyObserver.didReceive(_:)))
        observer.isRegistrationFinished = true

        storage.set(2, forKey: key.id)
        storage.set(3, forKey: key.id)

        XCTAssertEqual(observer.callbacks, [.init(value: 1, isAfterRegistration: false)])
    }

    func test_register_registrationDuringFirstReadSharesKey() {
        let key = PersistentKey("com.example.key.\(#function)", defaultValue: 0)
        let firstObserver = RecordingKeyObserver()
        let secondObserver = RecordingKeyObserver()

        // The second registration is made on the reading thread before the first read returns, so it shares that read.
        storage.instrument(key.id)
        storage.afterNextRead { [storage] in
            storage?.register(
                observer: secondObserver,
                for: key,
                with: nil,
                and: #selector(RecordingKeyObserver.didReceive(_:))
            )
        }

        storage.register(observer: firstObserver, for: key, with: nil, and: #selector(RecordingKeyObserver.didReceive(_:)))

        XCTAssertEqual(storage.readCount, 1)

        storage.instrument(key.id)
        storage.set(1, forKey: key.id)

        XCTAssertEqual(storage.readCount, 1)
        XCTAssertEqual(firstObserver.observations.count, 1)
        XCTAssertEqual(secondObserver.observations.count, 1)

        storage.deregister(firstObserver, for: key, context: nil)
        storage.deregister(secondObserver, for: key, context: nil)
    }

    func test_register_deregistrationDuringFirstReadIsNotActivated() {
        let key = PersistentKey("com.example.key.\(#function)", defaultValue: 0)
        let observer = RecordingKeyObserver()

        storage.instrument(key.id)
        storage.afterNextRead { [storage] in
            storage?.deregister(observer, for: key, context: nil)
        }

        storage.register(observer: observer, for: key, with: nil, and: #selector(RecordingKeyObserver.didReceive(_:)))

        storage.instrument(key.id)
        storage.set(1, forKey: key.id)

        XCTAssertEqual(storage.readCount, 0)
        XCTAssertTrue(observer.observations.isEmpty)
    }

    func test_publisher_subscriptionFromChangeCallbackDeliversItsFirstChange() {
        let outerKey = PersistentKey("com.example.outer.\(#function)", defaultValue: 0)
        let innerKey = PersistentKey("com.example.inner.\(#function)", defaultValue: 0)
        var innerSubscription: AnyCancellable?
        var innerValues: [Int] = []

        // The inner subscription registers, reads, and writes its key while the outer change is being reconciled.
        let outerSubscription = storage.publisher(for: outerKey, emitsInitialValue: false).sink { [storage] _ in
            guard innerSubscription == nil, let storage else {
                return
            }

            innerSubscription = storage.publisher(for: innerKey).sink { value in
                innerValues.append(value)
            }

            storage.set(innerKey, to: 2)
        }

        storage.set(outerKey, to: 1)

        XCTAssertEqual(storage.get(innerKey), 2)
        XCTAssertEqual(innerValues, [0, 2])

        storage.set(innerKey, to: 3)

        XCTAssertEqual(innerValues, [0, 2, 3])

        outerSubscription.cancel()
        innerSubscription?.cancel()
    }

    func test_changesPublisher_subscriptionFromFirstReadJoinsIt() throws {
        let key = PersistentKey("com.example.key.\(#function)", defaultValue: 0)
        let storage = try XCTUnwrap(LazilySubscribingUserDefaults(suiteName: suiteName))
        let observer = RecordingKeyObserver()

        // The getter subscribes to the key the first time it is read, so registration reenters itself.
        storage.lazilySubscribedKey = key
        storage.register(observer: observer, for: key, with: nil, and: #selector(RecordingKeyObserver.didReceive(_:)))

        XCTAssertEqual(storage.readCount, 1)
        XCTAssertEqual(storage.changeCount, 0)

        storage.set(key, to: 1)

        XCTAssertEqual(storage.changeCount, 1)
        XCTAssertEqual(observer.observations.count, 1)

        storage.cancelSubscription()
        storage.deregister(observer, for: key, context: nil)
    }

    func test_register_concurrentChangesDeliverLatestValue() async {
        let key = PersistentKey("com.example.key.\(#function)", defaultValue: 0)
        let recorder = LatestValueRecorder()
        // `UserDefaults` is thread-safe but not declared `Sendable`.
        nonisolated(unsafe) let storage: UserDefaults = storage

        let cancellable = storage.publisher(for: key).sink { value in
            recorder.record(value)
        }

        await withTaskGroup(of: Void.self) { group in
            for writer in 0 ..< 4 {
                group.addTask {
                    for value in 1 ... 50 {
                        storage.set(writer * 100 + value, forKey: key.id)
                    }
                }
            }
        }

        storage.set(-1, forKey: key.id)

        XCTAssertEqual(recorder.latestValue, -1)

        cancellable.cancel()
    }
}

// MARK: - Shared Read Tests

extension UserDefaultsKeyChangeObservationTests {
    // MARK: Tests

    func test_register_notifiesOnlyWhenCollectionValueChanges() {
        let observer = RecordingKeyObserver()
        let key = PersistentKey("com.example.key.\(#function)", defaultValue: [String]())

        storage.set(key, to: ["first"])
        storage.register(observer: observer, for: key, with: nil, and: #selector(RecordingKeyObserver.didReceive(_:)))

        storage.set(1, forKey: "com.example.unrelated.\(#function)")
        storage.set(key, to: ["first"])
        storage.set(2, forKey: "com.example.unrelated.\(#function)")

        XCTAssertTrue(observer.observations.isEmpty)

        storage.set(key, to: ["first", "second"])

        XCTAssertEqual(observer.observations.count, 1)

        storage.deregister(observer, for: key, context: nil)
    }

    func test_register_registrationsForSameKeyShareOneRead() {
        let key = PersistentKey("com.example.key.\(#function)", defaultValue: 0)
        let observers = (0 ..< 3).map { _ in
            RecordingKeyObserver()
        }

        for observer in observers {
            storage.register(observer: observer, for: key, with: nil, and: #selector(RecordingKeyObserver.didReceive(_:)))
        }

        storage.instrument(key.id)
        storage.set(1, forKey: "com.example.unrelated.\(#function)")

        XCTAssertEqual(storage.readCount, 1)
        XCTAssertTrue(observers.allSatisfy { $0.observations.isEmpty })

        storage.instrument(key.id)
        storage.set(1, forKey: key.id)

        XCTAssertEqual(storage.readCount, 1)
        XCTAssertTrue(observers.allSatisfy { $0.observations.count == 1 })

        for observer in observers {
            storage.deregister(observer, for: key, context: nil)
        }

        storage.instrument(key.id)
        storage.set(2, forKey: key.id)

        XCTAssertEqual(storage.readCount, 0)
    }

    func test_register_registrationsWithSameValueShareOneComparison() throws {
        let key = PersistentKey("com.example.key.\(#function)", defaultValue: Data())
        let storage = try XCTUnwrap(StubbedUserDefaults(suiteName: suiteName))
        let observers = (0 ..< 3).map { _ in
            RecordingKeyObserver()
        }
        let comparisonValue = EqualityCallbackData([1])

        storage.stubbedObject = comparisonValue

        for observer in observers {
            storage.register(observer: observer, for: key, with: nil, and: #selector(RecordingKeyObserver.didReceive(_:)))
        }

        storage.stubbedObject = EqualityCallbackData([2])
        NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: storage)

        XCTAssertEqual(comparisonValue.equalityCheckCount, 1)
        XCTAssertTrue(observers.allSatisfy { $0.observations.count == 1 })

        for observer in observers {
            storage.deregister(observer, for: key, context: nil)
        }
    }

    func test_publisher_subscriptionJoiningObservedKeyComparesWithItsOwnValue() {
        let outerKey = PersistentKey("com.example.outer.\(#function)", defaultValue: 0)
        let innerKey = PersistentKey("com.example.inner.\(#function)", defaultValue: 0)
        var existingValues: [Int] = []
        var joiningSubscription: AnyCancellable?
        var joiningValues: [Int] = []

        storage.set(innerKey, to: 0)

        let existingSubscription = storage.publisher(for: innerKey).sink { value in
            existingValues.append(value)
        }

        // While the outer change is being reconciled, the inner key changes, gains a subscription, and changes back
        // to the value the existing subscription last received.
        let outerSubscription = storage.publisher(for: outerKey, emitsInitialValue: false).sink { [storage] _ in
            guard joiningSubscription == nil, let storage else {
                return
            }

            storage.set(innerKey, to: 1)

            joiningSubscription = storage.publisher(for: innerKey).sink { value in
                joiningValues.append(value)
            }

            storage.set(innerKey, to: 0)
        }

        storage.set(outerKey, to: 1)

        XCTAssertEqual(joiningValues, [1, 0])
        XCTAssertEqual(existingValues.last, 0)

        storage.set(innerKey, to: 3)

        XCTAssertEqual(joiningValues, [1, 0, 3])
        XCTAssertEqual(existingValues.last, 3)

        outerSubscription.cancel()
        joiningSubscription?.cancel()
        existingSubscription.cancel()
    }

    func test_publisher_subscriptionJoiningObservedKeyDoesNotReceiveItsFirstValueAgain() {
        let outerKey = PersistentKey("com.example.outer.\(#function)", defaultValue: 0)
        let innerKey = PersistentKey("com.example.inner.\(#function)", defaultValue: 0)
        var existingValues: [Int] = []
        var joiningSubscription: AnyCancellable?
        var joiningValues: [Int] = []

        storage.set(innerKey, to: 0)

        let existingSubscription = storage.publisher(for: innerKey).sink { value in
            existingValues.append(value)
        }

        // The inner key changes and gains a subscription before the existing subscription's change is reconciled.
        let outerSubscription = storage.publisher(for: outerKey, emitsInitialValue: false).sink { [storage] _ in
            guard joiningSubscription == nil, let storage else {
                return
            }

            storage.set(innerKey, to: 1)

            joiningSubscription = storage.publisher(for: innerKey).sink { value in
                joiningValues.append(value)
            }
        }

        storage.set(outerKey, to: 1)

        XCTAssertEqual(existingValues, [0, 1])
        XCTAssertEqual(joiningValues, [1])

        storage.set(innerKey, to: 2)

        XCTAssertEqual(existingValues, [0, 1, 2])
        XCTAssertEqual(joiningValues, [1, 2])

        outerSubscription.cancel()
        joiningSubscription?.cancel()
        existingSubscription.cancel()
    }

    func test_changesPublisher_subscriptionDuringComparisonDoesNotReceiveComparedValue() throws {
        let key = PersistentKey("com.example.key.\(#function)", defaultValue: Data())
        let storage = try XCTUnwrap(StubbedUserDefaults(suiteName: suiteName))
        let observer = RecordingKeyObserver()
        let comparisonValue = EqualityCallbackData([1])
        var subscription: AnyCancellable?
        var values: [Data] = []

        storage.stubbedObject = comparisonValue
        storage.register(observer: observer, for: key, with: nil, and: #selector(RecordingKeyObserver.didReceive(_:)))

        // The subscription is made while the changed value is compared with the existing registration's value, so the
        // change is already stored when it subscribes.
        comparisonValue.onEqualityCheck = {
            subscription = storage.changesPublisher(for: key).sink { value in
                values.append(value)
            }
        }
        storage.stubbedObject = EqualityCallbackData([2])
        NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: storage)

        XCTAssertNotNil(subscription)
        XCTAssertEqual(observer.observations.count, 1)
        XCTAssertEqual(values, [])

        storage.stubbedObject = EqualityCallbackData([3])
        NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: storage)

        XCTAssertEqual(observer.observations.count, 2)
        XCTAssertEqual(values, [Data([3])])

        subscription?.cancel()
        storage.deregister(observer, for: key, context: nil)
    }

    func test_register_observerDeregisteredByEarlierObserverIsNotNotified() {
        let key = PersistentKey("com.example.key.\(#function)", defaultValue: 0)
        let laterObserver = RecordingKeyObserver()
        let earlierObserver = DeregisteringKeyObserver(store: storage, key: key, deregistering: laterObserver)

        storage.register(observer: earlierObserver, for: key, with: nil, and: #selector(DeregisteringKeyObserver.didReceive(_:)))
        storage.register(observer: laterObserver, for: key, with: nil, and: #selector(RecordingKeyObserver.didReceive(_:)))

        storage.set(1, forKey: key.id)

        XCTAssertEqual(earlierObserver.callbackCount, 1)
        XCTAssertTrue(laterObserver.observations.isEmpty)
    }
}

// MARK: - Key Identity Tests

extension UserDefaultsKeyChangeObservationTests {
    // MARK: Tests

    func test_deregister_distinguishesCanonicallyEquivalentKeys() {
        let observer = RecordingKeyObserver()
        let composedKey = PersistentKey("caf\u{E9}.\(#function)", defaultValue: 0)
        let decomposedKey = PersistentKey("cafe\u{301}.\(#function)", defaultValue: 0)

        storage.register(observer: observer, for: composedKey, with: nil, and: #selector(RecordingKeyObserver.didReceive(_:)))
        storage.register(observer: observer, for: decomposedKey, with: nil, and: #selector(RecordingKeyObserver.didReceive(_:)))
        storage.deregister(observer, for: composedKey, context: nil)

        storage.set(1, forKey: composedKey.id)

        XCTAssertTrue(observer.observations.isEmpty)

        storage.set(1, forKey: decomposedKey.id)

        XCTAssertEqual(observer.observations.map(\.keyPath), [decomposedKey.id])
        XCTAssertTrue(observer.observations.first?.keyPath?.utf16.elementsEqual(decomposedKey.id.utf16) ?? false)

        storage.deregister(observer, for: decomposedKey, context: nil)
    }
}

// MARK: - Monitor Lifecycle Tests

extension UserDefaultsKeyChangeObservationTests {
    // MARK: Tests

    func test_monitor_doesNotActivateInvalidatedObservation() {
        let observer = RecordingKeyObserver()
        let keyID = "com.example.key.\(#function)"
        let observation = UserDefaultsKeyChangeObservation(
            observer: observer,
            keyID: keyID,
            context: nil,
            monitor: .monitor(for: storage)
        )

        // A deregistration that races registration invalidates the observation before it is activated.
        observation.invalidate()
        observation.activate()

        storage.instrument(keyID)
        storage.set(1, forKey: keyID)

        XCTAssertEqual(storage.readCount, 0)
        XCTAssertTrue(observer.observations.isEmpty)
    }

    func test_monitor_ignoresChangesAfterItsInstanceIsReleased() throws {
        let observer = RecordingKeyObserver()
        let keyID = "com.example.key.\(#function)"
        let monitor: UserDefaultsKeyChangeMonitor
        weak var releasedUserDefaults: UserDefaults?

        do {
            let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
            releasedUserDefaults = userDefaults
            monitor = .monitor(for: userDefaults)

            monitor.add(
                UserDefaultsKeyChangeObservation(observer: observer, keyID: keyID, context: nil, monitor: monitor)
            )
        }

        XCTAssertNil(releasedUserDefaults)

        storage.set(1, forKey: keyID)

        XCTAssertTrue(observer.observations.isEmpty)
    }
}

// MARK: - Lock Reentrancy Tests

extension UserDefaultsKeyChangeObservationTests {
    // MARK: Tests

    func test_register_releasingObserversWhileAnotherSuiteIsWrittenDoesNotDeadlock() throws {
        let isWriting = LockedFlag(true)
        let writersFinished = expectation(description: "Writers finished")
        let registrationsFinished = expectation(description: "Registrations finished")
        // `UserDefaults` is thread-safe but not declared `Sendable`. The instrumented instance's slower reads would
        // make the registering threads reconcile most changes themselves, so this uses a plain instance.
        nonisolated(unsafe) let storage = try XCTUnwrap(UserDefaults(suiteName: suiteName))

        writersFinished.expectedFulfillmentCount = 4
        registrationsFinished.expectedFulfillmentCount = 4

        // Each write reconciles this instance's observed keys on the writing thread, while the registering threads
        // release their observers, so a reconciliation can hold the last reference to one.
        for writer in 0 ..< 4 {
            let writerSuiteName = stableSuiteName("UserDefaultsKeyChangeObservationTests.writer\(writer)", function: name)

            addTeardownBlock {
                UserDefaults(suiteName: writerSuiteName)?.removePersistentDomain(forName: writerSuiteName)
            }

            Thread.detachNewThread {
                let writerStorage = UserDefaults(suiteName: writerSuiteName)!
                var value = 0

                while isWriting.value {
                    value += 1

                    autoreleasepool {
                        writerStorage.set(value, forKey: "writer")
                    }
                }

                writersFinished.fulfill()
            }
        }

        // Each registering thread observes its own key, so every reconciliation checks each thread's observer.
        for registrant in 0 ..< 4 {
            let key = PersistentKey("com.example.key\(registrant).\(#function)", defaultValue: 0)

            Thread.detachNewThread {
                let deadline = Date(timeIntervalSinceNow: 3)

                while Date() < deadline {
                    autoreleasepool {
                        let iterator = PersistentKeyValues(key, store: storage).makeAsyncIterator()
                        withExtendedLifetime(iterator) {}

                        let observer = SelfDeregisteringKeyObserver(store: storage, key: key)
                        storage.register(
                            observer: observer,
                            for: key,
                            with: nil,
                            and: #selector(SelfDeregisteringKeyObserver.didReceive(_:))
                        )
                    }
                }

                registrationsFinished.fulfill()
            }
        }

        waitDetachingMonitorOnTimeout(for: [registrationsFinished], of: storage)
        isWriting.value = false
        waitDetachingMonitorOnTimeout(for: [writersFinished], of: storage)
    }

    func test_register_equalityCheckCanDeregister() throws {
        let key = PersistentKey("com.example.key.\(#function)", defaultValue: Data())
        // The stub is configured before the posting thread starts.
        nonisolated(unsafe) let storage = try XCTUnwrap(StubbedUserDefaults(suiteName: suiteName))
        let observer = RecordingKeyObserver()
        let comparisonValue = EqualityCallbackData([1])
        let posted = expectation(description: "Change posted")

        storage.stubbedObject = comparisonValue
        storage.register(observer: observer, for: key, with: nil, and: #selector(RecordingKeyObserver.didReceive(_:)))

        comparisonValue.onEqualityCheck = {
            storage.deregister(observer, for: key, context: nil)
        }
        storage.stubbedObject = EqualityCallbackData([2])

        // Post on another thread, so a deadlock fails the wait instead of blocking the test process.
        Thread.detachNewThread {
            NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: storage)
            posted.fulfill()
        }

        waitDetachingMonitorOnTimeout(for: [posted], of: storage)

        XCTAssertEqual(comparisonValue.equalityCheckCount, 1)
        XCTAssertTrue(observer.observations.isEmpty)
    }

    // MARK: Private Instance Interface

    /// Waits for `expectations`, failing after a bounded timeout.
    ///
    /// A deadlocked monitor would block every later defaults change in the process, so on timeout the monitor stops
    /// receiving change notifications and later tests can still run.
    private func waitDetachingMonitorOnTimeout(
        for expectations: [XCTestExpectation],
        of userDefaults: UserDefaults,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard XCTWaiter.wait(for: expectations, timeout: 30) != .completed else {
            return
        }

        NotificationCenter.default.removeObserver(UserDefaultsKeyChangeMonitor.monitor(for: userDefaults))
        XCTFail("Timed out waiting for \(expectations.map(\.description)); the monitor deadlocked", file: file, line: line)
    }
}

// MARK: - DeregisteringKeyObserver Definition

/// An observer that deregisters itself, or another observer, when it receives its first callback.
private final class DeregisteringKeyObserver: NSObject, @unchecked Sendable {
    /// A callback, with the key's value when it was delivered.
    struct Callback: Equatable {
        let value: Int
        let isAfterRegistration: Bool
    }

    private(set) var callbacks: [Callback] = []

    /// Whether the test's registration call has returned.
    var isRegistrationFinished = false

    var callbackCount: Int {
        callbacks.count
    }

    private let key: PersistentKey<Int>
    private let observerToDeregister: NSObject?
    private let store: UserDefaults

    init(store: UserDefaults, key: PersistentKey<Int>, deregistering observerToDeregister: NSObject? = nil) {
        self.key = key
        self.observerToDeregister = observerToDeregister
        self.store = store
    }

    @objc
    func didReceive(_ notification: Notification) {
    }

    override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey: Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        callbacks.append(Callback(value: store.get(key), isAfterRegistration: isRegistrationFinished))

        store.deregister(observerToDeregister ?? self, for: key, context: nil)
    }
}

// MARK: - EqualityCallbackData Definition

/// Data that runs an action, once, the first time it is compared for equality.
private final class EqualityCallbackData: NSData, @unchecked Sendable {
    /// The action to run during the first equality check. Set before the comparing thread starts.
    var onEqualityCheck: (() -> Void)?

    private(set) var equalityCheckCount = 0

    private let storage: NSData

    init(_ bytes: [UInt8]) {
        storage = Data(bytes) as NSData

        super.init()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var bytes: UnsafeRawPointer {
        storage.bytes
    }

    override var length: Int {
        storage.length
    }

    override func isEqual(_ object: Any?) -> Bool {
        equalityCheckCount += 1

        let action = onEqualityCheck
        onEqualityCheck = nil
        action?()

        return storage.isEqual(object)
    }
}

// MARK: - SelfDeregisteringKeyObserver Definition

/// An observer that deregisters itself when it is deinitialized, as observation types in the package do.
private final class SelfDeregisteringKeyObserver: NSObject, @unchecked Sendable {
    private let key: PersistentKey<Int>
    private let store: UserDefaults

    init(store: UserDefaults, key: PersistentKey<Int>) {
        self.key = key
        self.store = store
    }

    deinit {
        store.deregister(self, for: key, context: nil)
    }

    @objc
    func didReceive(_ notification: Notification) {
    }

    override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey: Any]?,
        context: UnsafeMutableRawPointer?
    ) {
    }
}

// MARK: - StubbedUserDefaults Definition

/// A `UserDefaults` subclass that returns one stubbed object for every key.
private final class StubbedUserDefaults: UserDefaults {
    /// The object returned for every key. Set before the reading thread starts.
    var stubbedObject: Any?

    override func object(forKey defaultName: String) -> Any? {
        stubbedObject
    }
}

// MARK: - LatestValueRecorder Definition

/// Records the latest value delivered on any thread.
private final class LatestValueRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Int?

    var latestValue: Int? {
        lock.lock()
        defer {
            lock.unlock()
        }

        return value
    }

    func record(_ value: Int) {
        lock.lock()
        defer {
            lock.unlock()
        }

        self.value = value
    }
}

// MARK: - LazilySubscribingUserDefaults Definition

/// A `UserDefaults` subclass that subscribes to changes of one key the first time that key is read.
private final class LazilySubscribingUserDefaults: UserDefaults {
    /// The key to subscribe to. Set before the key is first read.
    var lazilySubscribedKey: PersistentKey<Int>?

    /// The number of changes the subscription received.
    private(set) var changeCount = 0

    /// The number of reads of the subscribed key.
    private(set) var readCount = 0

    private var subscription: AnyCancellable?

    // MARK: Internal Instance Interface

    func cancelSubscription() {
        subscription?.cancel()
        subscription = nil
    }

    // MARK: UserDefaults Implementation

    override func object(forKey defaultName: String) -> Any? {
        if let lazilySubscribedKey, lazilySubscribedKey.id.utf16.elementsEqual(defaultName.utf16) {
            readCount += 1

            if subscription == nil {
                subscription = changesPublisher(for: lazilySubscribedKey).sink { [weak self] _ in
                    self?.changeCount += 1
                }
            }
        }

        return super.object(forKey: defaultName)
    }
}
