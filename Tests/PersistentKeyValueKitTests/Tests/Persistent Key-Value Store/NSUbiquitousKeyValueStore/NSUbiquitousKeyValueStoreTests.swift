//
//  NSUbiquitousKeyValueStoreTests.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 4/28/24.
//

import Foundation
import PersistentKeyValueKit
import XCTest

@available(watchOS 9.0, *)
final class NSUbiquitousKeyValueStoreTests: AbstractPersistentKeyValueStoreTests<NSUbiquitousKeyValueStore> {
    private let storage: NSUbiquitousKeyValueStore = MockUbiquitousKeyValueStore()
    
    // MARK: AbstractPersistentKeyValueStoreTests Implementation
    
    override var target: NSUbiquitousKeyValueStore {
        storage
    }
    
    // MARK: XCTestCase Implementation
    
    override public func tearDown() {
        storage.dictionaryRepresentation.keys.forEach(storage.removeObject)
    }
    
    // MARK: Static Accessor Tests
    
    @MainActor
    func test_staticAccessor() {
        XCTAssert(NSUbiquitousKeyValueStore.default === NSUbiquitousKeyValueStore.ubiquitous)
    }
    
    // MARK: PersistentKeyValueStore Tests
    
    @MainActor
    func test_persistentKeyValueStore_remove() {
        let keyID = "key"
        let defaultValue = "defaultValue"
        let storedValue = "storedValue"
        
        let key = PersistentKey(keyID, defaultValue: defaultValue)
        
        storage.set(storedValue, forKey: key.id)
        storage.remove(key)
        
        XCTAssertNil(storage.dictionaryRepresentation[keyID])
    }
}

// MARK: - Observation Tests

@available(watchOS 9.0, *)
extension NSUbiquitousKeyValueStoreTests {
    // MARK: Tests

    @MainActor
    func test_deregister_removesOnlyMatchingContext() {
        let observer = RecordingKeyObserver()
        let key = PersistentKey("key:\(#function)", defaultValue: "defaultValue")
        let firstContext = UnsafeMutableRawPointer(bitPattern: 1)
        let secondContext = UnsafeMutableRawPointer(bitPattern: 2)

        storage.register(observer: observer, for: key, with: firstContext, and: #selector(RecordingKeyObserver.didReceive(_:)))
        storage.register(observer: observer, for: key, with: secondContext, and: #selector(RecordingKeyObserver.didReceive(_:)))
        storage.deregister(observer, for: key, context: firstContext)

        storage.set("changedValue", forKey: key.id)

        XCTAssertEqual(observer.notifications.count, 1)

        storage.deregister(observer, for: key, context: secondContext)
    }

    @MainActor
    func test_deregister_removesOnlyMatchingKey() {
        let observer = RecordingKeyObserver()
        let firstKey = PersistentKey("firstKey:\(#function)", defaultValue: "defaultValue")
        let secondKey = PersistentKey("secondKey:\(#function)", defaultValue: "defaultValue")

        storage.register(observer: observer, for: firstKey, with: nil, and: #selector(RecordingKeyObserver.didReceive(_:)))
        storage.register(observer: observer, for: secondKey, with: nil, and: #selector(RecordingKeyObserver.didReceive(_:)))
        storage.deregister(observer, for: firstKey, context: nil)

        storage.set("changedValue", forKey: secondKey.id)

        XCTAssertEqual(observer.notifications.count, 1)

        observer.reset()
        storage.set("changedValue", forKey: firstKey.id)

        XCTAssertEqual(observer.notifications.count, 0)

        storage.deregister(observer, for: secondKey, context: nil)
    }

    @MainActor
    func test_register_deliversNotificationsThatMayChangeEveryKey() {
        let observer = RecordingKeyObserver()
        let key = PersistentKey("key:\(#function)", defaultValue: "defaultValue")

        storage.register(observer: observer, for: key, with: nil, and: #selector(RecordingKeyObserver.didReceive(_:)))

        NotificationCenter.default.post(
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: storage,
            userInfo: [
                NSUbiquitousKeyValueStoreChangeReasonKey: NSUbiquitousKeyValueStoreAccountChange,
            ]
        )
        NotificationCenter.default.post(
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: storage,
            userInfo: nil
        )
        NotificationCenter.default.post(
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: storage,
            userInfo: [
                NSUbiquitousKeyValueStoreChangeReasonKey: NSUbiquitousKeyValueStoreServerChange,
                NSUbiquitousKeyValueStoreChangedKeysKey: [
                    "unrelatedKey:\(#function)",
                ],
            ]
        )

        XCTAssertEqual(observer.notifications.count, 2)

        storage.deregister(observer, for: key, context: nil)
    }

    @MainActor
    func test_register_deliversOnlyChangesToRegisteredKey() {
        let observer = RecordingKeyObserver()
        let firstKey = PersistentKey("firstKey:\(#function)", defaultValue: "defaultValue")
        let secondKey = PersistentKey("secondKey:\(#function)", defaultValue: "defaultValue")

        storage.register(observer: observer, for: firstKey, with: nil, and: #selector(RecordingKeyObserver.didReceive(_:)))
        storage.register(observer: observer, for: secondKey, with: nil, and: #selector(RecordingKeyObserver.didReceive(_:)))

        storage.set("changedValue", forKey: firstKey.id)

        XCTAssertEqual(observer.notifications.count, 1)
        XCTAssertEqual(
            observer.notifications.first?.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String],
            [firstKey.id]
        )

        storage.deregister(observer, for: firstKey, context: nil)
        storage.deregister(observer, for: secondKey, context: nil)
    }

    @MainActor
    func test_register_releasesDeallocatedObserver() {
        let key = PersistentKey("key:\(#function)", defaultValue: "defaultValue")
        let survivingObserver = RecordingKeyObserver()
        weak var releasedObserver: RecordingKeyObserver?

        do {
            let observer = RecordingKeyObserver()
            releasedObserver = observer

            storage.register(observer: observer, for: key, with: nil, and: #selector(RecordingKeyObserver.didReceive(_:)))
        }

        XCTAssertNil(releasedObserver)

        // Delivery skips the deallocated observer, and the next registration releases its registration.
        storage.set("changedValue", forKey: key.id)
        storage.register(observer: survivingObserver, for: key, with: nil, and: #selector(RecordingKeyObserver.didReceive(_:)))
        storage.set("otherValue", forKey: key.id)

        XCTAssertEqual(survivingObserver.notifications.count, 1)

        storage.deregister(survivingObserver, for: key, context: nil)
    }
}
