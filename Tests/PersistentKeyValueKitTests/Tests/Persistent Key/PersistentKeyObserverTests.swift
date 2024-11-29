//
//  PersistentKeyObserverTests.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 10/4/24.
//

import PersistentKeyValueKit
import XCTest

final class PersistentKeyObserverTests: XCTestCase {
    private let userDefaults: UserDefaults = .standard
    
    // MARK: XCTestCase Implementation
    
    override func tearDown() {
        userDefaults.dictionaryRepresentation().keys.forEach(userDefaults.removeObject)
        userDefaults.setVolatileDomain([:], forName: UserDefaults.registrationDomain)
    }
}

// MARK: - Initialization Tests

extension PersistentKeyObserverTests {
    // MARK: Tests
    
    @MainActor
    func test_init_userDefaults() {
        let key = PersistentKey("testKey", defaultValue: "defaultValue")
        let observer = PersistentKeyUIObservableObject(store: userDefaults, key: key)
        
        XCTAssertNotNil(observer)
        XCTAssertEqual(observer.key.id, "testKey")
        XCTAssertEqual(observer.value, "defaultValue")
    }
    
    @available(watchOS 9.0, *)
    @MainActor
    func test_init_ubiquitousKeyValueStore() {
        let ubiquitousKeyValueStore: NSUbiquitousKeyValueStore = MockUbiquitousKeyValueStore()
        let key = PersistentKey("testKey", defaultValue: "defaultValue")
        let observer = PersistentKeyUIObservableObject(store: ubiquitousKeyValueStore, key: key)
        
        XCTAssertNotNil(observer)
        XCTAssertEqual(observer.key.id, "testKey")
        XCTAssertEqual(observer.value, "defaultValue")
    }
}

// MARK: - Value Tests

extension PersistentKeyObserverTests {
    // MARK: Tests
    
    @MainActor
    func test_value_get() {
        let key = PersistentKey("testKey", defaultValue: "defaultValue")
        let observer = PersistentKeyUIObservableObject(store: userDefaults, key: key)
        
        XCTAssertEqual(observer.value, "defaultValue")
        
        userDefaults.set("newValue", forKey: "testKey")
        XCTAssertEqual(observer.value, "newValue")
    }
    
    @MainActor
    func test_value_set() {
        let key = PersistentKey("testKey", defaultValue: "defaultValue")
        let observer = PersistentKeyUIObservableObject(store: userDefaults, key: key)
        
        observer.value = "newValue"
        XCTAssertEqual(observer.value, "newValue")
        XCTAssertEqual(userDefaults.string(forKey: "testKey"), "newValue")
    }
}

// MARK: - Observation Tests

extension PersistentKeyObserverTests {
    // MARK: Tests
    
    @MainActor
    func test_observation_userDefaultsChangesObserved() {
        let expectation = self.expectation(description: "Value change observed")
        expectation.expectedFulfillmentCount = 2
        let key = PersistentKey("testKey", defaultValue: "defaultValue")
        let observer = PersistentKeyUIObservableObject(store: userDefaults, key: key)
        
        let cancellable = observer.objectWillChange.sink {
            expectation.fulfill()
        }
        
        userDefaults.set("newValue1", forKey: "testKey")
        userDefaults.set("newValue2", forKey: "testKey")
        
        waitForExpectations(timeout: 1.0)
        cancellable.cancel()
    }
}

// MARK: - Store Change Tests

extension PersistentKeyObserverTests {
    // MARK: Tests
    
    @available(watchOS 9.0, *)
    @MainActor
    func test_store_changeUpdatesValueAndObservation() {
        let ubiquitousKeyValueStore: NSUbiquitousKeyValueStore = MockUbiquitousKeyValueStore()
        let key = PersistentKey("testKey", defaultValue: "defaultValue")
        let observer = PersistentKeyUIObservableObject(store: userDefaults, key: key)
        
        userDefaults.set("userDefaultsValue", forKey: "testKey")
        XCTAssertEqual(observer.value, "userDefaultsValue")
        
        observer.store = ubiquitousKeyValueStore
        XCTAssertEqual(observer.value, "defaultValue")
        
        ubiquitousKeyValueStore.set("ubiquitousValue", forKey: "testKey")
        XCTAssertEqual(observer.value, "ubiquitousValue")
    }
}

// MARK: - Deinitialization Tests

extension PersistentKeyObserverTests {
    // MARK: Tests
    
    @MainActor
    func test_deinitialization_observerRemoved() {
        let key = PersistentKey("testKey", defaultValue: "defaultValue")
        var observer: PersistentKeyUIObservableObject? = PersistentKeyUIObservableObject(store: userDefaults, key: key)
        
        weak var weakObserver = observer
        observer = nil
        
        XCTAssertNil(weakObserver, "Observer should be deallocated")
    }
}
