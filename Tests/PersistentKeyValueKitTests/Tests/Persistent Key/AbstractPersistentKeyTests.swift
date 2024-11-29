//
//  AbstractPersistentKeyTests.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 10/4/24.
//

import PersistentKeyValueKit
import XCTest

public class AbstractPersistentKeyTests<Key>: XCTestCase where Key: PersistentKeyProtocol, Key.Value: Equatable {
    public let userDefaults = UserDefaults()
    
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
    
    override public func tearDown() {
        userDefaults.dictionaryRepresentation().keys.forEach(userDefaults.removeObject)
        userDefaults.setVolatileDomain([:], forName: UserDefaults.registrationDomain)
    }

    // MARK: Initialization Tests

    @MainActor
    func test_init() {
        XCTAssertEqual(target.id, id)
        XCTAssertEqual(target.defaultValue, defaultValue)
    }
    
    // MARK: PersistentKeyProtocol Tests
    
    @available(watchOS 9.0, *)
    @MainActor
    func test_persistentKey_ubiquitousKeyValueStore_get_defaultValue() {
        let ubiquitousKeyValueStore: NSUbiquitousKeyValueStore = MockUbiquitousKeyValueStore()
        
        XCTAssertEqual(target.get(from: ubiquitousKeyValueStore), defaultValue)
    }

    @available(watchOS 9.0, *)
    @MainActor
    func test_persistentKey_ubiquitousKeyValueStore_get_storedValue() {
        let ubiquitousKeyValueStore: NSUbiquitousKeyValueStore = MockUbiquitousKeyValueStore()
        
        ubiquitousKeyValueStore.set(storedValue, forKey: id)
        
        XCTAssertEqual(target.get(from: ubiquitousKeyValueStore), storedValue)
    }

    @available(watchOS 9.0, *)
    @MainActor
    func test_persistentKey_ubiquitousKeyValueStore_remove_noValue() {
        let ubiquitousKeyValueStore: NSUbiquitousKeyValueStore = MockUbiquitousKeyValueStore()
        
        target.remove(from: ubiquitousKeyValueStore)
        
        XCTAssertNil(ubiquitousKeyValueStore.dictionaryRepresentation[id])
    }

    @available(watchOS 9.0, *)
    @MainActor
    func test_persistentKey_ubiquitousKeyValueStore_remove_storedValue() {
        let ubiquitousKeyValueStore: NSUbiquitousKeyValueStore = MockUbiquitousKeyValueStore()
        
        ubiquitousKeyValueStore.set(storedValue, forKey: id)
        
        target.remove(from: ubiquitousKeyValueStore)
        
        XCTAssertNil(ubiquitousKeyValueStore.dictionaryRepresentation[id])
    }
    
    @available(watchOS 9.0, *)
    @MainActor
    func test_persistentKey_ubiquitousKeyValueStore_set() {
        let ubiquitousKeyValueStore: NSUbiquitousKeyValueStore = MockUbiquitousKeyValueStore()
        
        target.set(to: storedValue, in: ubiquitousKeyValueStore)
        
        XCTAssertEqual(ubiquitousKeyValueStore.dictionaryRepresentation[id] as? Key.Value, storedValue)
    }

    @MainActor
    func test_persistentKey_userDefaults_get_defaultValue() {
        XCTAssertEqual(target.get(from: userDefaults), defaultValue)
    }
    
    @MainActor
    func test_persistentKey_userDefaults_get_storedValue() {
        userDefaults.set(storedValue, forKey: id)
        
        XCTAssertEqual(target.get(from: userDefaults), storedValue)
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
        
        XCTAssertNil(userDefaults.dictionaryRepresentation()[id])
    }
    
    @MainActor
    func test_persistentKey_userDefaults_set() {
        target.set(to: storedValue, in: userDefaults)
        
        XCTAssertEqual(userDefaults.dictionaryRepresentation()[id] as? Key.Value, storedValue)
    }
    
    // MARK: Internal Instance Interface
    
    /// Skip the test if the environment is not iOS 16, or later, or equivalent.
    ///
    /// There is an issue with the implementation of tryCast across the Objective-C bridge when testing on
    /// iOS 15 from Xcode 16. Additionally, marking test cases as available <= iOS 16 is not working in the
    /// same environment.
    func skipIfNotiOS16OrLaterOrEquivalent() throws {
        guard #available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *) else {
            throw XCTSkip(">= iOS 16 is required for this test.")
        }
    }
}
