//
//  NSUbiquitousKeyValueStoreObservationTests.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 11/17/26.
//

import Foundation
import PersistentKeyValueKit
import XCTest

@available(watchOS 9.0, *)
final class NSUbiquitousKeyValueStoreObservationTests: XCTestCase {
    private let storage: NSUbiquitousKeyValueStore = MockUbiquitousKeyValueStore()
}

// MARK: - Registration Tests

@available(watchOS 9.0, *)
extension NSUbiquitousKeyValueStoreObservationTests {
    // MARK: Tests

    func test_register_callbackDuringRegistrationCanDeregister() {
        let key = PersistentKey("key:\(#function)", defaultValue: 0)
        let observer = DeregisteringNotificationObserver(store: storage, key: key)

        NotificationObserverInstallationHook.perform(
            afterInstallingObserverFor: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            action: { [storage] in
                Self.postExternalChange(to: [key.id], from: storage)
            },
            during: {
                storage.register(
                    observer: observer,
                    for: key,
                    with: nil,
                    and: #selector(DeregisteringNotificationObserver.didReceive(_:))
                )
            }
        )

        Self.postExternalChange(to: [key.id], from: storage)
        storage.set(key, to: 3)

        XCTAssertEqual(observer.callbackCount, 1)
    }
}

// MARK: - Key Identity Tests

@available(watchOS 9.0, *)
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

// MARK: - Test Utilities

@available(watchOS 9.0, *)
extension NSUbiquitousKeyValueStoreObservationTests {
    private static func postExternalChange(to keyIDs: [String], from store: NSUbiquitousKeyValueStore) {
        NotificationCenter.default.post(
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store,
            userInfo: [
                NSUbiquitousKeyValueStoreChangeReasonKey: NSUbiquitousKeyValueStoreServerChange,
                NSUbiquitousKeyValueStoreChangedKeysKey: keyIDs,
            ]
        )
    }
}

// MARK: - DeregisteringNotificationObserver Definition

/// An observer that deregisters itself when it receives its first notification.
@available(watchOS 9.0, *)
private final class DeregisteringNotificationObserver: NSObject {
    private(set) var callbackCount = 0

    private let key: PersistentKey<Int>
    private let store: NSUbiquitousKeyValueStore

    init(store: NSUbiquitousKeyValueStore, key: PersistentKey<Int>) {
        self.key = key
        self.store = store
    }

    @objc
    func didReceive(_ notification: Notification) {
        callbackCount += 1

        store.deregister(self, for: key, context: nil)
    }
}
