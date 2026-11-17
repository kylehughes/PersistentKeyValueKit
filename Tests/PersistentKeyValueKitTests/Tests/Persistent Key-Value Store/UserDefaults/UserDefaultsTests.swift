//
//  UserDefaultsTests.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 3/28/22.
//

import Foundation
import PersistentKeyValueKit
import XCTest

final class UserDefaultsTests: AbstractPersistentKeyValueStoreTests<UserDefaults> {
    private var storage: UserDefaults!
    private var suiteName: String!
    
    // MARK: AbstractPersistentKeyValueStoreTests Implementation
    
    override var target: UserDefaults {
        storage
    }
    
    // MARK: XCTestCase Implementation
    
    override public func setUpWithError() throws {
        suiteName = stableSuiteName("UserDefaultsTests", function: name)
        storage = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }
    
    override public func tearDown() {
        storage.removePersistentDomain(forName: suiteName)
        storage.setVolatileDomain([:], forName: UserDefaults.registrationDomain)
        storage = nil
        suiteName = nil
    }
    
    // MARK: Static Accessor Tests
    
    @MainActor
    func test_staticAccessor() {
        XCTAssert(UserDefaults.standard === UserDefaults.local)
    }
    
    // MARK: PersistentKeyValueStore Tests
    
    @MainActor
    func test_persistentKeyValueStore_registerDefaults_existingKeys() {
        let keyID = "stringKey"
        let defaultValue = "defaultString"
        let existingValue = "existingString"
        
        let key = PersistentKey(keyID, defaultValue: defaultValue)
        
        storage.set(existingValue, forKey: keyID)
        storage.register([key])
        
        XCTAssertEqual(storage.string(forKey: keyID), existingValue)
    }
    
    @MainActor
    func test_persistentKeyValueStore_registerDefaults_nonexistingKeys() {
        let stringKeyID = "stringKey"
        let intKeyID = "intKey"
        let boolKeyID = "boolKey"
        
        let stringDefaultValue = "defaultString"
        let intDefaultValue = 42
        let boolDefaultValue = true
        
        let stringKey = PersistentKey(stringKeyID, defaultValue: stringDefaultValue)
        let intKey = PersistentKey(intKeyID, defaultValue: intDefaultValue)
        let boolKey = PersistentKey(boolKeyID, defaultValue: boolDefaultValue)
        
        storage.register([stringKey, intKey, boolKey])
        
        XCTAssertEqual(storage.string(forKey: stringKeyID), stringDefaultValue)
        XCTAssertEqual(storage.integer(forKey: intKeyID), intDefaultValue)
        XCTAssertEqual(storage.bool(forKey: boolKeyID), boolDefaultValue)
    }
    
    @MainActor
    func test_persistentKeyValueStore_registerDefaults_unregistered() {
        let unregisteredKeyID = "unregisteredKey"
        
        XCTAssertNil(storage.string(forKey: unregisteredKeyID))
    }
    
    @MainActor
    func test_persistentKeyValueStore_registerDefaults_variadic() {
        let stringKeyID = "stringKey"
        let intKeyID = "intKey"
        let boolKeyID = "boolKey"
        
        let stringDefaultValue = "defaultString"
        let intDefaultValue = 42
        let boolDefaultValue = true
        
        let stringKey = PersistentKey(stringKeyID, defaultValue: stringDefaultValue)
        let intKey = PersistentKey(intKeyID, defaultValue: intDefaultValue)
        let boolKey = PersistentKey(boolKeyID, defaultValue: boolDefaultValue)
        
        storage.register(stringKey, intKey, boolKey)
        
        XCTAssertEqual(storage.string(forKey: stringKeyID), stringDefaultValue)
        XCTAssertEqual(storage.integer(forKey: intKeyID), intDefaultValue)
        XCTAssertEqual(storage.bool(forKey: boolKeyID), boolDefaultValue)
    }
    
    @MainActor
    func test_persistentKeyValueStore_remove() {
        let keyID = "key"
        let defaultValue = "defaultValue"
        let storedValue = "storedValue"
        
        let key = PersistentKey(keyID, defaultValue: defaultValue)
        
        storage.set(storedValue, forKey: key.id)
        storage.remove(key)
        
        XCTAssertNil(storage.dictionaryRepresentation()[keyID])
    }
}

// MARK: - Observation Tests

extension UserDefaultsTests {
    // MARK: Tests

    @MainActor
    func test_deregister_keyWithPeriods_removesOnlyMatchingRegistration() {
        let observer = RecordingKeyObserver()
        let firstKey = PersistentKey("com.example.first.\(#function)", defaultValue: 0)
        let secondKey = PersistentKey("com.example.second.\(#function)", defaultValue: 0)
        let firstContext = UnsafeMutableRawPointer(bitPattern: 1)
        let secondContext = UnsafeMutableRawPointer(bitPattern: 2)

        storage.register(observer: observer, for: firstKey, with: firstContext, and: #selector(RecordingKeyObserver.didReceive(_:)))
        storage.register(observer: observer, for: firstKey, with: secondContext, and: #selector(RecordingKeyObserver.didReceive(_:)))
        storage.register(observer: observer, for: secondKey, with: firstContext, and: #selector(RecordingKeyObserver.didReceive(_:)))
        storage.deregister(observer, for: firstKey, context: firstContext)

        storage.set(1, forKey: firstKey.id)

        XCTAssertEqual(observer.observations.map(\.context), [secondContext])

        observer.reset()
        storage.set(1, forKey: secondKey.id)

        XCTAssertEqual(observer.observations.map(\.keyPath), [secondKey.id])

        storage.deregister(observer, for: firstKey, context: secondContext)
        storage.deregister(observer, for: secondKey, context: firstContext)
        observer.reset()
        storage.set(2, forKey: firstKey.id)
        storage.set(2, forKey: secondKey.id)

        XCTAssertTrue(observer.observations.isEmpty)
    }

    @MainActor
    func test_register_keyWithPeriods_ignoresUnchangedValues() {
        let observer = RecordingKeyObserver()
        let key = PersistentKey("com.example.key.\(#function)", defaultValue: 0)

        storage.set(1, forKey: key.id)
        storage.register(observer: observer, for: key, with: nil, and: #selector(RecordingKeyObserver.didReceive(_:)))

        storage.set(1, forKey: key.id)
        storage.set(1, forKey: "com.example.unrelated.\(#function)")

        XCTAssertTrue(observer.observations.isEmpty)

        storage.deregister(observer, for: key, context: nil)
    }

    @MainActor
    func test_register_keyWithPeriods_notifiesObserver() {
        let observer = RecordingKeyObserver()
        let key = PersistentKey("com.example.key.\(#function)", defaultValue: 0)
        let context = UnsafeMutableRawPointer(bitPattern: 1)

        storage.register(observer: observer, for: key, with: context, and: #selector(RecordingKeyObserver.didReceive(_:)))
        storage.set(key, to: 1)

        XCTAssertEqual(observer.observations.count, 1)
        XCTAssertEqual(observer.observations.first?.keyPath, key.id)
        XCTAssertEqual(observer.observations.first?.context, context)
        XCTAssertTrue(observer.observations.first?.object === storage)

        observer.reset()
        storage.remove(key)

        XCTAssertEqual(observer.observations.count, 1)

        storage.deregister(observer, for: key, context: context)
    }

    @MainActor
    func test_register_keyWithPeriods_observesAnotherInstanceForSuite() throws {
        let observer = RecordingKeyObserver()
        let key = PersistentKey("com.example.key.\(#function)", defaultValue: 0)
        let otherInstance = try XCTUnwrap(UserDefaults(suiteName: suiteName))

        storage.register(observer: observer, for: key, with: nil, and: #selector(RecordingKeyObserver.didReceive(_:)))
        otherInstance.set(1, forKey: key.id)

        XCTAssertEqual(observer.observations.count, 1)

        storage.deregister(observer, for: key, context: nil)
    }

    @MainActor
    func test_register_keyWithPeriods_releasesDeallocatedObserver() {
        let key = PersistentKey("com.example.key.\(#function)", defaultValue: 0)
        let survivingObserver = RecordingKeyObserver()
        weak var releasedObserver: RecordingKeyObserver?

        do {
            let observer = RecordingKeyObserver()
            releasedObserver = observer

            storage.register(observer: observer, for: key, with: nil, and: #selector(RecordingKeyObserver.didReceive(_:)))
        }

        XCTAssertNil(releasedObserver)

        // Delivery skips the deallocated observer, and the next registration releases its registration.
        storage.set(1, forKey: key.id)
        storage.register(observer: survivingObserver, for: key, with: nil, and: #selector(RecordingKeyObserver.didReceive(_:)))
        storage.set(2, forKey: key.id)

        XCTAssertEqual(survivingObserver.observations.count, 1)

        storage.deregister(survivingObserver, for: key, context: nil)
    }

    @MainActor
    func test_register_keyWithoutPeriods_usesKeyValueObservation() {
        let observer = RecordingKeyObserver()
        let key = PersistentKey("key:\(#function)", defaultValue: 0)

        storage.register(observer: observer, for: key, with: nil, and: #selector(RecordingKeyObserver.didReceive(_:)))
        storage.set(key, to: 1)

        XCTAssertEqual(observer.observations.map(\.keyPath), [key.id])

        storage.deregister(observer, for: key, context: nil)
        observer.reset()
        storage.set(key, to: 2)

        XCTAssertTrue(observer.observations.isEmpty)
    }
}
