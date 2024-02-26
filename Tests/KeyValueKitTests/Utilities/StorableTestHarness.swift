//
//  StorableTestHarness.swift
//  CodeMonkeyAppleTests
//
//  Created by Kyle Hughes on 4/18/22.
//

import Foundation
import KeyValueKit
import XCTest

struct StorableTestHarness<Target> where Target: Equatable & Storable {
    private let firstValue: Target
    private let secondValue: Target
    private let storage: UserDefaults
    
    // MARK: Internal Initialization
    
    init(firstValue: Target, secondValue: Target, storage: UserDefaults) {
        self.firstValue = firstValue
        self.secondValue = secondValue
        self.storage = storage
    }
    
    // MARK: Getting Value Tests
    
    func test() {
        test_default_nonoptional()
        test_default_optional()
        test_set_nonoptional()
        test_set_optional_from()
        test_set_optional_to()
    }
    
    func test_default_nonoptional() {
        typealias Value = Target
        let defaultValue: Value = firstValue
        let expectedValue: Value = defaultValue
        
        let key = StorageKey<Value>(id: UUID().uuidString, defaultValue: defaultValue)
        
        XCTAssertEqual(storage.get(key), expectedValue)
    }
    
    func test_default_optional() {
        typealias Value = Target?
        let defaultValue: Value = nil
        let expectedValue: Value = defaultValue
        
        let key = StorageKey<Value>(id: UUID().uuidString, defaultValue: defaultValue)
        
        XCTAssertEqual(storage.get(key), expectedValue)
    }
    
    func test_set_nonoptional() {
        typealias Value = Target
        let defaultValue: Value = firstValue
        let expectedValue: Value = secondValue
        
        let key = StorageKey<Value>(id: UUID().uuidString, defaultValue: defaultValue)
        storage.set(key, to: expectedValue)

        XCTAssertEqual(storage.get(key), expectedValue)
    }
    
    func test_set_optional_from() {
        typealias Value = Target?
        let defaultValue: Value = nil
        let expectedValue: Value = secondValue
        
        let key = StorageKey<Value>(id: UUID().uuidString, defaultValue: defaultValue)
        storage.set(key, to: expectedValue)
        
        let newValue: Value = storage.get(key)
        
        XCTAssertEqual(newValue, expectedValue)
    }
    
    func test_set_optional_to() {
        typealias Value = Target?
        let defaultValue: Value = firstValue
        let expectedValue: Value = nil
        
        let key = StorageKey<Value>(id: UUID().uuidString, defaultValue: defaultValue)
        storage.set(key, to: expectedValue)
        
        XCTAssertNil(storage.object(forKey: key.id))
    }
}
