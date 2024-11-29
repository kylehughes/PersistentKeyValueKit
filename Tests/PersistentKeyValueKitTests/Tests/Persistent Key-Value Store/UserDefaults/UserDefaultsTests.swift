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
    private let storage = UserDefaults.standard
    
    // MARK: AbstractPersistentKeyValueStoreTests Implementation
    
    override var target: UserDefaults {
        storage
    }
    
    // MARK: XCTestCase Implementation
    
    override public func tearDown() {
        storage.dictionaryRepresentation().keys.forEach(storage.removeObject)
        storage.setVolatileDomain([:], forName: UserDefaults.registrationDomain)
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
