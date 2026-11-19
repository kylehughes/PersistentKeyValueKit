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

/// Tests observation of `UserDefaults` keys that key-value observation cannot observe, such as keys whose identifiers
/// contain a period.
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

    func test_register_notifiesWhenOnlyIntegerWidthChanges() throws {
        // A read returns an in-process write as written, which a representation can decode by its width. Foundation
        // can ignore a write that Core Foundation considers equal, so the stub returns each read directly.
        let storage = try XCTUnwrap(StubbedUserDefaults(suiteName: suiteName))
        let key = PersistentKey("com.example.key.\(#function)", defaultValue: 0)
        let narrow = { NSNumber(value: Int32(-200_000_023)) }
        let wide = NSNumber(value: Int64(-200_000_023))
        let reads: [(original: Any, sameWidth: Any, widened: Any)] = [
            (narrow(), narrow(), wide),
            (NSArray(object: narrow()), NSArray(object: narrow()), NSArray(object: wide)),
            (NSDictionary(object: narrow(), forKey: "field" as NSString),
             NSDictionary(object: narrow(), forKey: "field" as NSString),
             NSDictionary(object: wide, forKey: "field" as NSString)),
        ]

        for read in reads {
            let observer = RecordingKeyObserver()

            storage.stubbedObject = read.original
            storage.register(observer: observer, for: key, with: nil, and: #selector(RecordingKeyObserver.didReceive(_:)))

            storage.stubbedObject = read.sameWidth
            NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: storage)

            XCTAssertTrue(observer.observations.isEmpty, "\(read.original)")

            storage.stubbedObject = read.widened
            NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: storage)

            XCTAssertEqual(observer.observations.count, 1, "\(read.original)")

            storage.deregister(observer, for: key, context: nil)
        }
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

    func test_register_registrationsWithSameNumberShareOneComparison() throws {
        let key = PersistentKey("com.example.key.\(#function)", defaultValue: 0)
        let storage = try XCTUnwrap(StubbedUserDefaults(suiteName: suiteName))
        let sharedValue = ComparisonCountingDecimalNumber(value: 1)
        let joiningValue = ComparisonCountingDecimalNumber(value: 2)
        let sharingObservers = (0 ..< 3).map { _ in
            RecordingKeyObserver()
        }
        let joiningObserver = RecordingKeyObserver()

        storage.stubbedObject = sharedValue.number

        for observer in sharingObservers {
            storage.register(observer: observer, for: key, with: nil, and: #selector(RecordingKeyObserver.didReceive(_:)))
        }

        // The joining registration's first comparison value is a different number, so it is compared separately.
        storage.stubbedObject = joiningValue.number
        storage.register(observer: joiningObserver, for: key, with: nil, and: #selector(RecordingKeyObserver.didReceive(_:)))

        storage.stubbedObject = NSDecimalNumber(mantissa: 2, exponent: 0, isNegative: false)
        NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: storage)

        XCTAssertEqual(sharedValue.comparisonCount, 1)
        XCTAssertEqual(joiningValue.comparisonCount, 1)
        XCTAssertTrue(sharingObservers.allSatisfy { $0.observations.count == 1 })
        XCTAssertTrue(joiningObserver.observations.isEmpty)

        for observer in sharingObservers + [joiningObserver] {
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

    func test_publisher_subscriptionJoiningObservedKeyReceivesChangeReportedDuringItsFirstRead() {
        let outerKey = PersistentKey("com.example.outer.\(#function)", defaultValue: 0)
        let innerKey = PersistentKey("com.example.inner.\(#function)", defaultValue: 0)
        var existingValues: [Int] = []
        var joiningSubscription: AnyCancellable?
        var joiningValues: [Int] = []

        storage.set(innerKey, to: 0)

        let existingSubscription = storage.publisher(for: innerKey).sink { value in
            existingValues.append(value)
        }

        // While the outer change is being reconciled, the inner key changes to `1`. Another write stores `2` after the
        // joining subscription's first comparison read returns `1` and before its initial value is read, and the key
        // then changes back to `1`.
        let outerSubscription = storage.publisher(for: outerKey, emitsInitialValue: false).sink { [storage] _ in
            guard joiningSubscription == nil, let storage else {
                return
            }

            storage.set(innerKey, to: 1)

            storage.instrument(innerKey.id)
            storage.afterNextRead {
                storage.set(2, forKey: innerKey.id)
            }

            joiningSubscription = storage.publisher(for: innerKey).sink { value in
                joiningValues.append(value)
            }

            storage.set(innerKey, to: 1)
        }

        storage.set(outerKey, to: 1)

        XCTAssertEqual(storage.get(innerKey), 1)
        XCTAssertEqual(joiningValues, [2, 1])
        XCTAssertEqual(existingValues, [0, 1])

        storage.set(innerKey, to: 3)

        XCTAssertEqual(joiningValues, [2, 1, 3])
        XCTAssertEqual(existingValues, [0, 1, 3])

        outerSubscription.cancel()
        joiningSubscription?.cancel()
        existingSubscription.cancel()
    }

    func test_values_iterationJoiningObservedKeyReceivesChangeReportedDuringItsFirstRead() async {
        let outerKey = PersistentKey("com.example.outer.\(#function)", defaultValue: 0)
        let innerKey = PersistentKey("com.example.inner.\(#function)", defaultValue: 0)
        var joiningIterator: PersistentKeyValues<PersistentKey<Int>>.Iterator?

        storage.set(innerKey, to: 0)

        // The joining iterator reads its initial value after another write replaces the value its first comparison
        // read returned, and the key then changes back to that value.
        let outerSubscription = storage.publisher(for: outerKey, emitsInitialValue: false).sink { [storage] _ in
            guard joiningIterator == nil, let storage else {
                return
            }

            storage.set(innerKey, to: 1)

            storage.instrument(innerKey.id)
            storage.afterNextRead {
                storage.set(2, forKey: innerKey.id)
            }

            joiningIterator = PersistentKeyValues(innerKey, store: storage, bufferingPolicy: .unbounded)
                .makeAsyncIterator()

            storage.set(innerKey, to: 1)
        }

        storage.set(outerKey, to: 1)

        XCTAssertEqual(storage.get(innerKey), 1)

        // A later change ends the wait for the restored value if that value is not delivered.
        storage.set(innerKey, to: 3)

        let initialValue = await joiningIterator?.next()
        let restoredValue = await joiningIterator?.next()

        XCTAssertEqual(initialValue, 2)
        XCTAssertEqual(restoredValue, 1)

        outerSubscription.cancel()
        joiningIterator = nil
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

    func test_register_keyPathIncompatibleKeys_notifiesObserver() {
        defer {
            storage.setVolatileDomain([:], forName: UserDefaults.registrationDomain)
        }

        for keyID in keyPathIncompatibleKeyIDs() {
            let message = "\(keyID.unicodeScalars.map(\.value))"
            let observer = RecordingKeyObserver()
            let key = PersistentKey(keyID, defaultValue: 5)

            storage.register(key)

            XCTAssertEqual(storage.get(key), 5, message)

            storage.register(observer: observer, for: key, with: nil, and: #selector(RecordingKeyObserver.didReceive(_:)))
            storage.set(key, to: 1)
            storage.remove(key)

            XCTAssertEqual(storage.get(key), 5, message)
            XCTAssertEqual(observer.observations.map(\.keyPath), [keyID, keyID], message)

            storage.deregister(observer, for: key, context: nil)
            observer.reset()
            storage.set(key, to: 2)

            XCTAssertTrue(observer.observations.isEmpty, message)
        }
    }

    func test_supportsKeyValueObservation_acceptsOnlyLiteralKeyPaths() {
        for keyID in keyPathIncompatibleKeyIDs() + ["com.example.key", "a.\u{301}"] {
            XCTAssertFalse(UserDefaults.supportsKeyValueObservation(of: keyID), "\(keyID.unicodeScalars.map(\.value))")
        }

        // Key-value observation reports changes to these keys, including those made by other processes.
        for keyID in ["key", " ", "a@count", "key:value", "valueForKey", "\u{FF0E}", "\u{2024}", " @key"] {
            XCTAssertTrue(UserDefaults.supportsKeyValueObservation(of: keyID), "\(keyID.unicodeScalars.map(\.value))")
        }
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

    func test_deregister_keyIdentifierCharactersRegisterAnotherKey_doesNotDeadlock() {
        nonisolated(unsafe) let storage: UserDefaults = self.storage
        let name = "com.example.key.\(#function).pr\u{E9}f\u{E9}rence"
        let identifier = AccessObservingString.make(name)
        let key = PersistentKey(identifier as String, defaultValue: 0)
        let otherKey = PersistentKey("com.example.other.\(#function)", defaultValue: 0)
        let observer = RecordingKeyObserver()
        let otherObserver = RecordingKeyObserver()
        let accessed = LockedFlag(false)
        let deregistered = expectation(description: "Deregistered")

        storage.register(
            observer: observer,
            for: PersistentKey(name, defaultValue: 0),
            with: nil,
            and: #selector(RecordingKeyObserver.didReceive(_:))
        )
        identifier.onAccess = {
            storage.register(
                observer: otherObserver,
                for: otherKey,
                with: nil,
                and: #selector(RecordingKeyObserver.didReceive(_:))
            )
            storage.deregister(otherObserver, for: otherKey, context: nil)
            accessed.value = true
        }

        // Deregister on another thread, so a deadlock fails the wait instead of blocking the test process.
        Thread.detachNewThread {
            storage.deregister(observer, for: key, context: nil)
            deregistered.fulfill()
        }

        waitDetachingMonitorOnTimeout(for: [deregistered], of: storage)
        identifier.onAccess = nil
        storage.set(1, forKey: name)

        XCTAssertTrue(accessed.value)
        XCTAssertTrue(observer.observations.isEmpty)
    }

    func test_deregister_releasingLastKeyIdentifierRegistersAnotherKey_doesNotDeadlock() {
        nonisolated(unsafe) let storage: UserDefaults = self.storage
        let name = "com.example.key.\(#function).pr\u{E9}f\u{E9}rence"
        let key = PersistentKey(name, defaultValue: 0)
        let otherKey = PersistentKey("com.example.other.\(#function)", defaultValue: 0)
        let firstObserver = RecordingKeyObserver()
        let secondObserver = RecordingKeyObserver()
        let otherObserver = RecordingKeyObserver()
        let released = expectation(description: "Identifier released")
        let deregistered = expectation(description: "Deregistered")

        // The first registration's identifier names the key's shared read, so it outlives that registration.
        autoreleasepool {
            let keyID = releaseObservingKeyID(name) {
                storage.register(
                    observer: otherObserver,
                    for: otherKey,
                    with: nil,
                    and: #selector(RecordingKeyObserver.didReceive(_:))
                )
                storage.deregister(otherObserver, for: otherKey, context: nil)
                released.fulfill()
            }

            storage.register(
                observer: firstObserver,
                for: PersistentKey(keyID, defaultValue: 0),
                with: nil,
                and: #selector(RecordingKeyObserver.didReceive(_:))
            )
        }

        storage.register(
            observer: secondObserver,
            for: key,
            with: nil,
            and: #selector(RecordingKeyObserver.didReceive(_:))
        )
        storage.deregister(firstObserver, for: key, context: nil)

        // Deregister on another thread, so a deadlock fails the wait instead of blocking the test process.
        Thread.detachNewThread {
            storage.deregister(secondObserver, for: key, context: nil)
            deregistered.fulfill()
        }

        waitDetachingMonitorOnTimeout(for: [released, deregistered], of: storage)
        storage.set(1, forKey: name)

        XCTAssertTrue(firstObserver.observations.isEmpty)
        XCTAssertTrue(secondObserver.observations.isEmpty)
    }

    func test_register_keyIdentifierCharactersRegisterAnotherKey_doesNotDeadlock() throws {
        // Foundation holds its own lock while it hashes a key it reads, so the stub keeps the identifier's accessor from
        // reentering Foundation. The stub is configured before the registering thread starts.
        nonisolated(unsafe) let storage = try XCTUnwrap(StubbedUserDefaults(suiteName: suiteName))
        let name = "com.example.key.\(#function).pr\u{E9}f\u{E9}rence"
        let identifier = AccessObservingString.make(name)
        let key = PersistentKey(identifier as String, defaultValue: 0)
        let otherKey = PersistentKey("com.example.other.\(#function)", defaultValue: 0)
        let firstObserver = RecordingKeyObserver()
        let secondObserver = RecordingKeyObserver()
        let otherObserver = RecordingKeyObserver()
        let accessed = LockedFlag(false)
        let registered = expectation(description: "Registered")

        // An existing registration for the key makes the second one join the key's shared read.
        storage.register(
            observer: firstObserver,
            for: PersistentKey(name, defaultValue: 0),
            with: nil,
            and: #selector(RecordingKeyObserver.didReceive(_:))
        )
        identifier.onAccess = {
            storage.register(
                observer: otherObserver,
                for: otherKey,
                with: nil,
                and: #selector(RecordingKeyObserver.didReceive(_:))
            )
            storage.deregister(otherObserver, for: otherKey, context: nil)
            accessed.value = true
        }

        // Register on another thread, so a deadlock fails the wait instead of blocking the test process.
        Thread.detachNewThread {
            storage.register(
                observer: secondObserver,
                for: key,
                with: nil,
                and: #selector(RecordingKeyObserver.didReceive(_:))
            )
            registered.fulfill()
        }

        guard waitDetachingMonitorOnTimeout(for: [registered], of: storage) else {
            return
        }

        identifier.onAccess = nil
        storage.stubbedObject = 1
        NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: storage)

        XCTAssertTrue(accessed.value)
        XCTAssertEqual(firstObserver.observations.count, 1)
        XCTAssertEqual(secondObserver.observations.count, 1)
        XCTAssertTrue(otherObserver.observations.isEmpty)

        storage.deregister(firstObserver, for: key, context: nil)
        storage.deregister(secondObserver, for: key, context: nil)
    }

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

    /// Waits for `expectations`, failing after a bounded timeout, and returns whether they were fulfilled.
    ///
    /// A deadlocked monitor would block every later defaults change in the process, so on timeout the monitor stops
    /// receiving change notifications and later tests can still run. Its lock stays held, so callers must not register
    /// or deregister with `userDefaults` after this returns `false`.
    @discardableResult
    private func waitDetachingMonitorOnTimeout(
        for expectations: [XCTestExpectation],
        of userDefaults: UserDefaults,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Bool {
        guard XCTWaiter.wait(for: expectations, timeout: 30) != .completed else {
            return true
        }

        NotificationCenter.default.removeObserver(UserDefaultsKeyChangeMonitor.monitor(for: userDefaults))
        XCTFail("Timed out waiting for \(expectations.map(\.description)); the monitor deadlocked", file: file, line: line)

        return false
    }
}

// MARK: - ComparisonCountingDecimalNumber Definition

/// A decimal number that counts how many times it is compared with another number.
///
/// Swift cannot subclass `NSNumber`, so the number's class is replaced with a runtime subclass whose `compare(_:)`
/// counts each call before calling the original implementation.
private final class ComparisonCountingDecimalNumber {
    let number: NSDecimalNumber

    var comparisonCount: Int {
        counter.count
    }

    private let counter = Counter()

    // MARK: Internal Initialization

    init(value: UInt64) {
        let selector = #selector(NSDecimalNumber.compare(_:))
        let number = NSDecimalNumber(mantissa: value, exponent: 0, isNegative: false)
        let method = class_getInstanceMethod(NSDecimalNumber.self, selector)!
        let originalCompare = unsafeBitCast(
            method_getImplementation(method),
            to: (@convention(c) (NSDecimalNumber, Selector, NSNumber) -> ComparisonResult).self
        )
        let subclass: AnyClass = objc_allocateClassPair(object_getClass(number), "ComparisonCountingDecimalNumber\(UUID())", 0)!
        let compare: @convention(block) (NSDecimalNumber, NSNumber) -> ComparisonResult = { [counter] number, other in
            counter.count += 1

            return originalCompare(number, selector, other)
        }

        class_addMethod(subclass, selector, imp_implementationWithBlock(compare), method_getTypeEncoding(method))
        objc_registerClassPair(subclass)
        object_setClass(number, subclass)

        self.number = number
    }

    // MARK: Counter Definition

    private final class Counter {
        var count = 0
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
