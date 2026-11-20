//
//  AbstractPersistentKeyTests.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 10/4/24.
//

import PersistentKeyValueKit
import XCTest

public class AbstractPersistentKeyTests<Key>: XCTestCase where Key: PersistentKeyProtocol, Key.Value: Equatable {
    public private(set) var userDefaults: UserDefaults!
    private var suiteName: String!
    
    // MARK: Public Abstract Interface
    
    public var defaultValue: Key.Value {
        fatalError("`defaultValue` needs to be implemented in a concrete subclass.")
    }
    
    public var id: String {
        fatalError("`id` needs to be implemented in a concrete subclass.")
    }
    
    public var storedValue: Key.Value {
        fatalError("`storedValue` needs to be implemented in a concrete subclass.")
    }

    public var supportsStoredValues: Bool {
        true
    }
    
    public var target: Key {
        fatalError("`target` needs to be implemented in a concrete subclass.")
    }
    
    // MARK: Public Class Interface
    
    public class var isAbstractTestCase: Bool {
        Self.self == AbstractPersistentKeyTests.self
    }
    
    // MARK: XCTestCase Implementation
    
    override public class var defaultTestSuite: XCTestSuite {
        guard isAbstractTestCase else {
            return super.defaultTestSuite
        }
        
        return XCTestSuite(name: "Empty Suite for \(Self.self)")
    }
    
    override public func setUpWithError() throws {
        suiteName = stableSuiteName("AbstractPersistentKeyTests", function: name)
        userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }
    
    override public func tearDown() {
        userDefaults.removePersistentDomain(forName: suiteName)
        userDefaults.setVolatileDomain([:], forName: UserDefaults.registrationDomain)
        userDefaults = nil
        suiteName = nil
    }

    // MARK: Initialization Tests

    @MainActor
    func test_init() {
        XCTAssertEqual(target.id, id)
        XCTAssertEqual(target.defaultValue, defaultValue)
    }
    
    // MARK: PersistentKeyProtocol Tests

    @MainActor
    func test_persistentKey_inMemoryStore_get_defaultValue() {
        let inMemoryStore = InMemoryPersistentKeyValueStore()

        XCTAssertEqual(target.get(from: inMemoryStore), defaultValue)
        XCTAssertEqual(inMemoryStore.get(target), defaultValue)
    }

    @MainActor
    func test_persistentKey_inMemoryStore_get_storedValue() {
        let inMemoryStore = InMemoryPersistentKeyValueStore()

        inMemoryStore.set(storedValue, forKey: id)

        if supportsStoredValues {
            XCTAssertEqual(target.get(from: inMemoryStore), storedValue)
            XCTAssertEqual(inMemoryStore.get(target), storedValue)
        } else {
            XCTAssertEqual(target.get(from: inMemoryStore), defaultValue)
            XCTAssertEqual(inMemoryStore.get(target), defaultValue)
        }
    }

    @MainActor
    func test_persistentKey_inMemoryStore_get_storedValueOfOtherType() {
        let inMemoryStore = InMemoryPersistentKeyValueStore()

        inMemoryStore.set(UUID(), forKey: id)

        XCTAssertEqual(target.get(from: inMemoryStore), defaultValue)
    }

    @MainActor
    func test_persistentKey_inMemoryStore_remove_noValue() {
        let inMemoryStore = InMemoryPersistentKeyValueStore()

        target.remove(from: inMemoryStore)

        XCTAssertNil(inMemoryStore.object(forKey: id))
    }

    @MainActor
    func test_persistentKey_inMemoryStore_remove_storedValue() {
        let inMemoryStore = InMemoryPersistentKeyValueStore()

        inMemoryStore.set(storedValue, forKey: id)
        inMemoryStore.remove(target)

        if supportsStoredValues {
            XCTAssertNil(inMemoryStore.object(forKey: id))
        } else {
            XCTAssertEqual(inMemoryStore.object(forKey: id) as? Key.Value, storedValue)
        }
    }

    @MainActor
    func test_persistentKey_inMemoryStore_set() {
        let inMemoryStore = InMemoryPersistentKeyValueStore()

        inMemoryStore.set(target, to: storedValue)

        if supportsStoredValues {
            XCTAssertEqual(inMemoryStore.object(forKey: id) as? Key.Value, storedValue)
        } else {
            XCTAssertNil(inMemoryStore.object(forKey: id))
        }
    }
    
    @MainActor
    func test_persistentKey_ubiquitousKeyValueStore_get_defaultValue() {
        let ubiquitousKeyValueStore: NSUbiquitousKeyValueStore = MockUbiquitousKeyValueStore()
        
        XCTAssertEqual(target.get(from: ubiquitousKeyValueStore), defaultValue)
    }

    @MainActor
    func test_persistentKey_ubiquitousKeyValueStore_get_storedValue() {
        let ubiquitousKeyValueStore: NSUbiquitousKeyValueStore = MockUbiquitousKeyValueStore()
        
        ubiquitousKeyValueStore.set(storedValue, forKey: id)
        
        if supportsStoredValues {
            XCTAssertEqual(target.get(from: ubiquitousKeyValueStore), storedValue)
        } else {
            XCTAssertEqual(target.get(from: ubiquitousKeyValueStore), defaultValue)
        }
    }

    @MainActor
    func test_persistentKey_ubiquitousKeyValueStore_remove_noValue() {
        let ubiquitousKeyValueStore: NSUbiquitousKeyValueStore = MockUbiquitousKeyValueStore()
        
        target.remove(from: ubiquitousKeyValueStore)
        
        XCTAssertNil(ubiquitousKeyValueStore.dictionaryRepresentation[id])
    }

    @MainActor
    func test_persistentKey_ubiquitousKeyValueStore_remove_storedValue() {
        let ubiquitousKeyValueStore: NSUbiquitousKeyValueStore = MockUbiquitousKeyValueStore()
        
        ubiquitousKeyValueStore.set(storedValue, forKey: id)
        
        target.remove(from: ubiquitousKeyValueStore)
        
        if supportsStoredValues {
            XCTAssertNil(ubiquitousKeyValueStore.dictionaryRepresentation[id])
        } else {
            XCTAssertEqual(ubiquitousKeyValueStore.dictionaryRepresentation[id] as? Key.Value, storedValue)
        }
    }
    
    @MainActor
    func test_persistentKey_ubiquitousKeyValueStore_set() {
        let ubiquitousKeyValueStore: NSUbiquitousKeyValueStore = MockUbiquitousKeyValueStore()
        
        target.set(to: storedValue, in: ubiquitousKeyValueStore)
        
        if supportsStoredValues {
            XCTAssertEqual(ubiquitousKeyValueStore.dictionaryRepresentation[id] as? Key.Value, storedValue)
        } else {
            XCTAssertNil(ubiquitousKeyValueStore.dictionaryRepresentation[id])
        }
    }

    @MainActor
    func test_persistentKey_userDefaults_get_defaultValue() {
        XCTAssertEqual(target.get(from: userDefaults), defaultValue)
    }
    
    @MainActor
    func test_persistentKey_userDefaults_get_storedValue() {
        userDefaults.set(storedValue, forKey: id)
        
        if supportsStoredValues {
            XCTAssertEqual(target.get(from: userDefaults), storedValue)
        } else {
            XCTAssertEqual(target.get(from: userDefaults), defaultValue)
        }
    }
    
    @MainActor
    func test_persistentKey_userDefaults_remove_noValue() {
        target.remove(from: userDefaults)
        
        XCTAssertNil(userDefaults.dictionaryRepresentation()[id])
    }

    @MainActor
    func test_persistentKey_userDefaults_remove_storedValue() {
        userDefaults.set(storedValue, forKey: id)
        target.remove(from: userDefaults)
        
        if supportsStoredValues {
            XCTAssertNil(userDefaults.dictionaryRepresentation()[id])
        } else {
            XCTAssertEqual(userDefaults.dictionaryRepresentation()[id] as? Key.Value, storedValue)
        }
    }
    
    @MainActor
    func test_persistentKey_userDefaults_set() {
        target.set(to: storedValue, in: userDefaults)
        
        if supportsStoredValues {
            XCTAssertEqual(userDefaults.dictionaryRepresentation()[id] as? Key.Value, storedValue)
        } else {
            XCTAssertNil(userDefaults.dictionaryRepresentation()[id])
        }
    }
}
