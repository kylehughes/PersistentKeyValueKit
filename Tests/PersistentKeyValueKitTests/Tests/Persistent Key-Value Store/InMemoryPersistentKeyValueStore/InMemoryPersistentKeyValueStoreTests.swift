//
//  InMemoryPersistentKeyValueStoreTests.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 4/28/24.
//

import Foundation
import PersistentKeyValueKit
import XCTest

final class InMemoryPersistentKeyValueStoreTests: AbstractPersistentKeyValueStoreTests<InMemoryPersistentKeyValueStore> {
    private let storage = InMemoryPersistentKeyValueStore()
    
    // MARK: AbstractPersistentKeyValueStoreTests Implementation
    
    override var target: InMemoryPersistentKeyValueStore {
        storage
    }
}

// MARK: - Observation Tests

extension InMemoryPersistentKeyValueStoreTests {
    func test_ephemeralCreatesIndependentUsableStores() {
        let key = PersistentKey("key:\(#function)", defaultValue: "defaultValue")
        let first: InMemoryPersistentKeyValueStore = .ephemeral
        let second: InMemoryPersistentKeyValueStore = .ephemeral

        first.set(key, to: "storedValue")

        XCTAssertEqual(first.get(key), "storedValue")
        XCTAssertEqual(second.get(key), "defaultValue")
    }

    func test_persistentKeyValueStore_deregister_stopsObservation() {
        let key = PersistentKey("key:\(#function)", defaultValue: "defaultValue")
        let observer = PersistentKeyValueStoreObservationRecorder()

        register(observer, for: key)
        target.deregister(observer, for: key, context: nil)
        target.set(key, to: "changedValue")

        XCTAssertTrue(observer.keyPaths.isEmpty)
    }

    func test_persistentKeyValueStore_deregister_byEarlierObserverStopsPendingNotification() {
        let key = PersistentKey("key:\(#function)", defaultValue: "defaultValue")
        let laterObserver = PersistentKeyValueStoreObservationRecorder()
        let earlierObserver = PersistentKeyValueStoreObservationRecorder()

        earlierObserver.onObservation = { [target] in
            target.deregister(laterObserver, for: key, context: nil)
        }

        register(earlierObserver, for: key)
        register(laterObserver, for: key)
        target.set(key, to: "changedValue")

        XCTAssertEqual(earlierObserver.keyPaths, [key.id])
        XCTAssertTrue(laterObserver.keyPaths.isEmpty)

        register(laterObserver, for: key)
        target.remove(key)

        XCTAssertEqual(earlierObserver.keyPaths, [key.id, key.id])
        XCTAssertTrue(laterObserver.keyPaths.isEmpty)
    }

    func test_persistentKeyValueStore_register_ignoresUnrelatedKeys() {
        let key = PersistentKey("key:\(#function)", defaultValue: "defaultValue")
        let observer = PersistentKeyValueStoreObservationRecorder()
        let unrelatedKey = PersistentKey("unrelatedKey:\(#function)", defaultValue: "unrelatedDefaultValue")

        register(observer, for: key)
        target.set(unrelatedKey, to: "changedValue")

        XCTAssertTrue(observer.keyPaths.isEmpty)
    }

    func test_persistentKeyValueStore_register_observesRemove() {
        let key = PersistentKey("key:\(#function)", defaultValue: "defaultValue")
        let observer = PersistentKeyValueStoreObservationRecorder()

        target.set(key, to: "storedValue")
        register(observer, for: key)
        target.remove(key)

        XCTAssertEqual(observer.keyPaths, [key.id])
    }

    func test_persistentKeyValueStore_register_observesSet() {
        let key = PersistentKey("key:\(#function)", defaultValue: "defaultValue")
        let observer = PersistentKeyValueStoreObservationRecorder()

        register(observer, for: key)
        target.set(key, to: "changedValue")

        XCTAssertEqual(observer.keyPaths, [key.id])
    }
}

private extension InMemoryPersistentKeyValueStoreTests {
    func register<Key>(
        _ observer: NSObject,
        for key: Key
    ) where Key: PersistentKeyProtocol {
        target.register(
            observer: observer,
            for: key,
            with: nil,
            and: #selector(NSObject.observeValue(forKeyPath:of:change:context:))
        )
    }
}

private final class PersistentKeyValueStoreObservationRecorder: NSObject {
    private(set) var keyPaths: [String?]

    /// Called after each recorded callback.
    var onObservation: (() -> Void)?

    override init() {
        keyPaths = []

        super.init()
    }

    override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey: Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        keyPaths.append(keyPath)
        onObservation?()
    }
}
