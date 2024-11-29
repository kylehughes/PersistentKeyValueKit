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
