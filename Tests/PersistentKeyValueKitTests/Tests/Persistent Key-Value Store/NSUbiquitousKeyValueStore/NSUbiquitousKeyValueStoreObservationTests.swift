//
//  NSUbiquitousKeyValueStoreObservationTests.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 11/17/26.
//

import Foundation
import PersistentKeyValueKit
import XCTest

final class NSUbiquitousKeyValueStoreObservationTests: XCTestCase {
    private let storage: NSUbiquitousKeyValueStore = MockUbiquitousKeyValueStore()
}

// MARK: - Registration Tests

extension NSUbiquitousKeyValueStoreObservationTests {
    // MARK: Tests

    func test_register_callbackDuringRegistrationCanDeregister() {
        let key = PersistentKey("key:\(#function)", defaultValue: 0)
        let observer = DeregisteringNotificationObserver(store: storage, key: key)

        // An unrelated store installing the same notification name first must not consume the hook.
        let unrelatedStore = MockUbiquitousKeyValueStore()
        let unrelatedObserver = RecordingKeyObserver()

        let didRunHook = NotificationObserverInstallationHook.perform(
            afterInstallingObserverFor: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: storage,
            action: { [storage] in
                Self.postExternalChange(to: [key.id], from: storage, phase: "registering")
            },
            during: {
                unrelatedStore.register(
                    observer: unrelatedObserver,
                    for: key,
                    with: nil,
                    and: #selector(RecordingKeyObserver.didReceive(_:))
                )
                storage.register(
                    observer: observer,
                    for: key,
                    with: nil,
                    and: #selector(DeregisteringNotificationObserver.didReceive(_:))
                )
            }
        )

        Self.postExternalChange(to: [key.id], from: storage, phase: "registered")
        storage.set(key, to: 3)

        XCTAssertTrue(didRunHook)
        XCTAssertEqual(observer.receivedPhases, ["registering"])
        XCTAssertTrue(unrelatedObserver.notifications.isEmpty)

        unrelatedStore.deregister(unrelatedObserver, for: key, context: nil)
    }
}

// MARK: - Key Identity Tests

extension NSUbiquitousKeyValueStoreObservationTests {
    // MARK: Tests

    func test_register_distinguishesCanonicallyEquivalentKeys() {
        let composedObserver = RecordingKeyObserver()
        let decomposedObserver = RecordingKeyObserver()
        let composedKey = PersistentKey("caf\u{E9}:\(#function)", defaultValue: 0)
        let decomposedKey = PersistentKey("cafe\u{301}:\(#function)", defaultValue: 0)

        storage.register(
            observer: composedObserver,
            for: composedKey,
            with: nil,
            and: #selector(RecordingKeyObserver.didReceive(_:))
        )
        storage.register(
            observer: decomposedObserver,
            for: decomposedKey,
            with: nil,
            and: #selector(RecordingKeyObserver.didReceive(_:))
        )

        Self.postExternalChange(to: [composedKey.id], from: storage)

        XCTAssertEqual(composedObserver.notifications.count, 1)
        XCTAssertEqual(decomposedObserver.notifications.count, 0)

        storage.deregister(composedObserver, for: composedKey, context: nil)
        storage.deregister(decomposedObserver, for: composedKey, context: nil)
        Self.postExternalChange(to: [decomposedKey.id], from: storage)

        XCTAssertEqual(composedObserver.notifications.count, 1)
        XCTAssertEqual(decomposedObserver.notifications.count, 1)

        storage.deregister(decomposedObserver, for: decomposedKey, context: nil)
    }

    func test_register_distinguishesKeysThatDifferOnlyInUnpairedSurrogates() {
        let keys = unpairedSurrogateKeyIDs("key:\(#function).").map {
            PersistentKey($0, defaultValue: 0)
        }
        let observers = keys.map { _ in
            RecordingKeyObserver()
        }

        for (key, observer) in zip(keys, observers) {
            storage.register(observer: observer, for: key, with: nil, and: #selector(RecordingKeyObserver.didReceive(_:)))
        }

        storage.deregister(observers[1], for: keys[0], context: nil)

        for (index, key) in keys.enumerated() {
            Self.postExternalChange(to: [key.id], from: storage)

            XCTAssertEqual(observers.map(\.notifications.count), keys.indices.map { $0 <= index ? 1 : 0 }, "\(index)")
        }

        for (key, observer) in zip(keys, observers) {
            storage.deregister(observer, for: key, context: nil)
        }
    }

    func test_publisher_ignoresChangeToCanonicallyEquivalentKey() {
        let composedKey = PersistentKey("caf\u{E9}:\(#function)", defaultValue: 0)
        let decomposedKey = PersistentKey("cafe\u{301}:\(#function)", defaultValue: 0)
        var values: [Int] = []

        let cancellable = decomposedKey.changesPublisher(in: storage).sink { value in
            values.append(value)
        }

        Self.postExternalChange(to: [composedKey.id], from: storage)

        XCTAssertEqual(values, [])

        cancellable.cancel()
    }
}

// MARK: - Lock Reentrancy Tests

extension NSUbiquitousKeyValueStoreObservationTests {
    // MARK: Tests

    func test_deregister_keyIdentifierCharactersRegisterAnotherKey_doesNotDeadlock() {
        nonisolated(unsafe) let storage = storage
        let name = "key:\(#function).pr\u{E9}f\u{E9}rence"
        let identifier = AccessObservingString.make(name)
        let key = PersistentKey(identifier as String, defaultValue: 0)
        let otherKey = PersistentKey("other:\(#function)", defaultValue: 0)
        let observer = RecordingKeyObserver()
        let otherObserver = RecordingKeyObserver()
        let accessed = LockedFlag(false)
        let deregistered = DispatchSemaphore(value: 0)

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
            deregistered.signal()
        }

        XCTAssertEqual(deregistered.wait(timeout: .now() + 5), .success, "The registry deadlocked.")

        identifier.onAccess = nil
        Self.postExternalChange(to: [name], from: storage)

        XCTAssertTrue(accessed.value)
        XCTAssertTrue(observer.notifications.isEmpty)
    }
}

// MARK: - Test Utilities

extension NSUbiquitousKeyValueStoreObservationTests {
    /// The `userInfo` key for the test phase in which a notification was posted.
    fileprivate static let phaseKey = "PersistentKeyValueKitTestPhase"

    private static func postExternalChange(
        to keyIDs: [String],
        from store: NSUbiquitousKeyValueStore,
        phase: String? = nil
    ) {
        var userInfo: [AnyHashable: Any] = [
            NSUbiquitousKeyValueStoreChangeReasonKey: NSUbiquitousKeyValueStoreServerChange,
            NSUbiquitousKeyValueStoreChangedKeysKey: keyIDs,
        ]

        userInfo[phaseKey] = phase

        NotificationCenter.default.post(
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store,
            userInfo: userInfo
        )
    }
}

// MARK: - DeregisteringNotificationObserver Definition

/// An observer that deregisters itself when it receives its first notification.
private final class DeregisteringNotificationObserver: NSObject {
    /// The test phase of each notification received, or `"unknown"` for one posted without a phase.
    private(set) var receivedPhases: [String] = []

    private let key: PersistentKey<Int>
    private let store: NSUbiquitousKeyValueStore

    init(store: NSUbiquitousKeyValueStore, key: PersistentKey<Int>) {
        self.key = key
        self.store = store
    }

    @objc
    func didReceive(_ notification: Notification) {
        let phase = notification.userInfo?[NSUbiquitousKeyValueStoreObservationTests.phaseKey] as? String

        receivedPhases.append(phase ?? "unknown")

        store.deregister(self, for: key, context: nil)
    }
}
