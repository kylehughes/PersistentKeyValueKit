//
//  AbstractKeyValuePersistibleTests.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 4/29/24.
//

import Foundation
import PersistentKeyValueKit
import XCTest

public class AbstractKeyValuePersistibleTests<
    Target,
    PropertyListRepresentation,
    UbiquitousStoreRepresentation,
    UserDefaultsRepresentation
>:
    XCTestCase
where
    Target: Equatable & KeyValuePersistible,
    PropertyListRepresentation: Equatable,
    UbiquitousStoreRepresentation: Equatable,
    UserDefaultsRepresentation: Equatable
{
    private let userDefaults = UserDefaults()
    
    // MARK: Public Abstract Interface
    
    public var expectations: [Expectation] {
        fatalError("`expectations` needs to be implemented in a concrete subclass.")
    }
    
    // MARK: Public Class Interface
        
    public class var isAbstractTestCase: Bool {
        self == AbstractKeyValuePersistibleTests.self
    }
    
    // MARK: XCTestCase Implementation
    
    override class public var defaultTestSuite: XCTestSuite {
        guard isAbstractTestCase else {
            return super.defaultTestSuite
        }

        return XCTestSuite(name: "Empty Suite for \(Self.self)")
    }
    
    override public func tearDown() {
        userDefaults.dictionaryRepresentation().keys.forEach(userDefaults.removeObject)
        userDefaults.setVolatileDomain([:], forName: UserDefaults.registrationDomain)
    }
    
    // MARK: Property List Array Tests
    
    @MainActor
    func test_persistentKeyValueRepresentation_array_get() {
        for expectation in expectations {
            let array: [Any] = [
                expectation.expectedPropertyListRepresentation,
                expectation.expectedPropertyListRepresentation,
            ]
            
            XCTAssertEqual(
                Target.persistentKeyValueRepresentation.get(from: array),
                [
                    expectation.target,
                    expectation.target
                ]
            )
        }
    }
    
    @MainActor
    func test_persistentKeyValueRepresentation_array_get_empty() {
        let array: [Any] = []
            
        XCTAssertEqual(Target.persistentKeyValueRepresentation.get(from: array), [])
    }
    
    @MainActor
    func test_persistentKeyValueRepresentation_array_get_wrong() {
        let array: [Any] = [
            CustomPersistibleType.Comprehensive.large,
            CustomPersistibleType.Comprehensive.small,
        ]
            
        XCTAssertNil(Target.persistentKeyValueRepresentation.get(from: array))
    }
    
    @MainActor
    func test_persistentKeyValueRepresentation_array_get_optional_empty() {
        let array: [Any] = []
            
        XCTAssertEqual(Target?.persistentKeyValueRepresentation.get(from: array), [])
    }
    
    @MainActor
    func test_persistentKeyValueRepresentation_array_get_optional_some() {
        for expectation in expectations {
            let array: [Any] = [
                expectation.expectedPropertyListRepresentation,
                expectation.expectedPropertyListRepresentation,
            ]
            
            XCTAssertEqual(
                Target?.persistentKeyValueRepresentation.get(from: array),
                [
                    expectation.target,
                    expectation.target,
                ]
            )
        }
    }
    
    @MainActor
    func test_persistentKeyValueRepresentation_array_get_optional_wrong() {
        let array: [Any] = [
            CustomPersistibleType.Comprehensive.large,
            CustomPersistibleType.Comprehensive.small,
        ]
            
        XCTAssertNil(Target?.persistentKeyValueRepresentation.get(from: array))
    }
    
    // MARK: Property List Dictionary Tests
    
    @MainActor
    func test_persistentKeyValueRepresentation_dictionary_get() {
        let key = "key"
        
        for expectation in expectations {
            var dictionary = [String: Any]()
            
            dictionary[key] = expectation.expectedPropertyListRepresentation
            
            XCTAssertEqual(
                Target.persistentKeyValueRepresentation.get(key, from: dictionary),
                expectation.target
            )
        }
    }
    
    @MainActor
    func test_persistentKeyValueRepresentation_dictionary_get_wrong() {
        let key = "key"
        
        var dictionary = [String: Any]()
        
        if Target.self != Int.self {
            dictionary[key] = 42
        } else {
            dictionary[key] = "wrong type string"
        }
        
        XCTAssertNil(Target.persistentKeyValueRepresentation.get(key, from: dictionary))
    }
    
    @MainActor
    func test_persistentKeyValueRepresentation_dictionary_get_optional_none() {
        let key = "key"
        
        let dictionary = [String: Any]()
                
        XCTAssertEqual(Target?.persistentKeyValueRepresentation.get(key, from: dictionary), .none)
    }
    
    @MainActor
    func test_persistentKeyValueRepresentation_dictionary_get_optional_some() {
        let key = "key"
        
        for expectation in expectations {
            var dictionary = [String: Any]()
            
            dictionary[key] = expectation.expectedPropertyListRepresentation
            
            XCTAssertEqual(
                Target?.persistentKeyValueRepresentation.get(key, from: dictionary),
                expectation.target
            )
        }
    }
    
    @MainActor
    func test_persistentKeyValueRepresentation_dictionary_get_optional_some_wrong() {
        let key = "key"
        
        var dictionary = [String: Any]()
        
        if Target.self != Int.self {
            dictionary[key] = 42
        } else {
            dictionary[key] = "wrong type string"
        }
        
        XCTAssertEqual(Target?.persistentKeyValueRepresentation.get(key, from: dictionary), .none)
    }
    
    @MainActor
    func test_persistentKeyValueRepresentation_dictionary_set() {
        let key = "key"
        
        for expectation in expectations {
            var dictionary = [String: Any]()
            
            Target.persistentKeyValueRepresentation.set(key, to: expectation.target, in: &dictionary)
            
            guard let castedObject = dictionary[key] as? PropertyListRepresentation else {
                XCTFail(
                    "Expected \(PropertyListRepresentation.self) but received " +
                    String(describing: dictionary[key]) +
                    " for \(expectation.target)."
                )
                continue
            }
            
            XCTAssertEqual(castedObject, expectation.expectedPropertyListRepresentation)
        }
    }
    
    @MainActor
    func test_persistentKeyValueRepresentation_dictionary_set_optional_none() {
        let key = "key"
        
        for expectation in expectations {
            var dictionary = [String: Any]()
            
            dictionary[key] = expectation.expectedPropertyListRepresentation
            
            Target?.persistentKeyValueRepresentation.set(key, to: nil, in: &dictionary)
            
            XCTAssertNil(dictionary.index(forKey: key))
        }
    }
    
    @MainActor
    func test_persistentKeyValueRepresentation_dictionary_set_optional_some() {
        let key = "key"
        
        for expectation in expectations {
            var dictionary = [String: Any]()
            
            Target?.persistentKeyValueRepresentation.set(key, to: expectation.target, in: &dictionary)
            
            guard let castedObject = dictionary[key] as? PropertyListRepresentation else {
                XCTFail(
                    "Expected \(PropertyListRepresentation.self) but received " +
                    String(describing: dictionary[key]) +
                    " for \(expectation.target)."
                )
                continue
            }
            
            XCTAssertEqual(castedObject, expectation.expectedPropertyListRepresentation)
        }
    }
    
    // MARK: Ubiquitous Key-Value Store Tests
    
    @available(watchOS 9.0, *)
    @MainActor
    func test_persistentKeyValueRepresentation_ubiquitousKeyValueStore_get() {
        let ubiquitousKeyValueStore: NSUbiquitousKeyValueStore = MockUbiquitousKeyValueStore()
        
        let key = "key"
        
        for expectation in expectations {
            ubiquitousKeyValueStore.set(expectation.expectedUbiquitousStoreRepresentation, forKey: key)
            
            XCTAssertEqual(
                Target.persistentKeyValueRepresentation.get(key, from: ubiquitousKeyValueStore),
                expectation.target
            )
        }
    }
    
    @available(watchOS 9.0, *)
    @MainActor
    func test_persistentKeyValueRepresentation_ubiquitousKeyValueStore_get_optional_none() {
        let ubiquitousKeyValueStore: NSUbiquitousKeyValueStore = MockUbiquitousKeyValueStore()
        
        let key = "key"
                
        XCTAssertEqual(Target?.persistentKeyValueRepresentation.get(key, from: ubiquitousKeyValueStore), nil)
    }
    
    @available(watchOS 9.0, *)
    @MainActor
    func test_persistentKeyValueRepresentation_ubiquitousKeyValueStore_get_optional_some() {
        let ubiquitousKeyValueStore: NSUbiquitousKeyValueStore = MockUbiquitousKeyValueStore()
        
        let key = "key"
        
        for expectation in expectations {
            ubiquitousKeyValueStore.set(expectation.expectedUbiquitousStoreRepresentation, forKey: key)
            
            XCTAssertEqual(
                Target?.persistentKeyValueRepresentation.get(key, from: ubiquitousKeyValueStore),
                expectation.target
            )
        }
    }
    
    @available(watchOS 9.0, *)
    @MainActor
    func test_persistentKeyValueRepresentation_ubiquitousKeyValueStore_set() {
        let ubiquitousKeyValueStore: NSUbiquitousKeyValueStore = MockUbiquitousKeyValueStore()
        
        let key = "key"
        
        for expectation in expectations {
            Target.persistentKeyValueRepresentation.set(key, to: expectation.target, in: ubiquitousKeyValueStore)
            
            guard let object = ubiquitousKeyValueStore.object(forKey: key) as? UbiquitousStoreRepresentation else {
                XCTFail(
                    "Expected \(UbiquitousStoreRepresentation.self) but received " +
                    String(describing: ubiquitousKeyValueStore.object(forKey: key)) +
                    " for \(expectation.target)."
                )
                
                continue
            }
            
            XCTAssertEqual(object, expectation.expectedUbiquitousStoreRepresentation)
        }
    }
    
    @available(watchOS 9.0, *)
    @MainActor
    func test_persistentKeyValueRepresentation_ubiquitousKeyValueStore_set_optional_none() {
        let ubiquitousKeyValueStore: NSUbiquitousKeyValueStore = MockUbiquitousKeyValueStore()
        
        let key = "key"
        
        for expectation in expectations {
            ubiquitousKeyValueStore.set(expectation.expectedUbiquitousStoreRepresentation, forKey: key)
            
            Target?.persistentKeyValueRepresentation.set(key, to: nil, in: ubiquitousKeyValueStore)
            
            XCTAssertNil(ubiquitousKeyValueStore.object(forKey: key))
        }
    }
    
    @available(watchOS 9.0, *)
    @MainActor
    func test_persistentKeyValueRepresentation_ubiquitousKeyValueStore_set_optional_some() {
        let ubiquitousKeyValueStore: NSUbiquitousKeyValueStore = MockUbiquitousKeyValueStore()
        
        let key = "key"
        
        for expectation in expectations {
            Target?.persistentKeyValueRepresentation.set(key, to: expectation.target, in: ubiquitousKeyValueStore)
            
            guard let object = ubiquitousKeyValueStore.object(forKey: key) as? UbiquitousStoreRepresentation? else {
                XCTFail(
                    "Expected \(UbiquitousStoreRepresentation?.self) but received " +
                    String(describing: ubiquitousKeyValueStore.object(forKey: key)) +
                    " for \(expectation.target)."
                )
                
                continue
            }
            
            XCTAssertEqual(object, expectation.expectedUbiquitousStoreRepresentation)
        }
    }
    
    // MARK: UserDefaults Tests
    
    @MainActor
    func test_persistentKeyValueRepresentation_userDefaults_get() {
        let key = "key"
        
        for expectation in expectations {
            set(expectation.expectedUserDefaultsRepresentation, for: key, in: userDefaults)
            
            XCTAssertEqual(
                Target.persistentKeyValueRepresentation.get(key, from: userDefaults),
                expectation.target
            )
        }
    }
    
    @MainActor
    func test_persistentKeyValueRepresentation_userDefaults_get_optional_none() {
        let key = "key"
        
        XCTAssertEqual(Target?.persistentKeyValueRepresentation.get(key, from: userDefaults), nil)
    }
    
    @MainActor
    func test_persistentKeyValueRepresentation_userDefaults_get_optional_some() {
        let key = "key"
        
        for expectation in expectations {
            set(expectation.expectedUserDefaultsRepresentation, for: key, in: userDefaults)
            
            XCTAssertEqual(
                Target?.persistentKeyValueRepresentation.get(key, from: userDefaults),
                expectation.target
            )
        }
    }
    
    @MainActor
    func test_persistentKeyValueRepresentation_userDefaults_set() {
        let key = "key"
        
        for expectation in expectations {
            Target.persistentKeyValueRepresentation.set(key, to: expectation.target, in: userDefaults)
            
            guard let object = get(for: key, in: userDefaults) else {
                XCTFail(
                    "Expected \(UserDefaultsRepresentation.self) but received " +
                    String(describing: userDefaults.object(forKey: key)) +
                    " for \(expectation.target)."
                )
                continue
            }
            
            XCTAssertEqual(object, expectation.expectedUserDefaultsRepresentation)
        }
    }
    
    @MainActor
    func test_persistentKeyValueRepresentation_userDefaults_set_optional_none() {
        let key = "key"
        
        for expectation in expectations {
            set(expectation.expectedUserDefaultsRepresentation, for: key, in: userDefaults)
            
            Target?.persistentKeyValueRepresentation.set(key, to: nil, in: userDefaults)
            
            XCTAssertNil(userDefaults.dictionaryRepresentation()[key])
        }
    }
    
    @MainActor
    func test_persistentKeyValueRepresentation_userDefaults_set_optional_some() {
        let key = "key"
        
        for expectation in expectations {
            Target?.persistentKeyValueRepresentation.set(key, to: Optional.some(expectation.target), in: userDefaults)
            
            guard let object = get(for: key, in: userDefaults) else {
                XCTFail(
                    "Expected \(UserDefaultsRepresentation?.self) but received " +
                    String(describing: userDefaults.object(forKey: key)) +
                    " for \(expectation.target)."
                )
                continue
            }
            
            XCTAssertEqual(object, expectation.expectedUserDefaultsRepresentation)
        }
    }
    
    // MARK: Private Instance Interface
    
    private func get(for key: String, in userDefaults: UserDefaults) -> UserDefaultsRepresentation? {
        /// URL is the only non-property-list type that is natively storable, but we need to go through its specific
        /// interface else we will get a runtime exception.
        guard UserDefaultsRepresentation.self != URL.self else {
            return userDefaults.url(forKey: key) as? UserDefaultsRepresentation
        }
        
        return userDefaults.object(forKey: key) as? UserDefaultsRepresentation
    }
    
    private func set(_ representation: UserDefaultsRepresentation, for key: String, in userDefaults: UserDefaults) {
        /// URL is the only non-property-list type that is natively storable, but we need to go through its specific
        /// interface else we will get a runtime exception.
        if let representation = representation as? URL {
            userDefaults.set(representation, forKey: key)
        } else {
            userDefaults.set(representation, forKey: key)
        }
    }
}

// MARK: - Expectation Definition

extension AbstractKeyValuePersistibleTests {
    public struct Expectation {
        public let expectedPropertyListRepresentation: PropertyListRepresentation
        public let expectedUbiquitousStoreRepresentation: UbiquitousStoreRepresentation
        public let expectedUserDefaultsRepresentation: UserDefaultsRepresentation
        public let target: Target
        
        // MARK: Public Initialization
        
        public init(
            _ target: @autoclosure () -> Target
        )
        where
            Target == PropertyListRepresentation,
            Target == UbiquitousStoreRepresentation,
            Target == UserDefaultsRepresentation
        {
            self.init(
                target: target(),
                propertyListRepresentation: \.self,
                ubiquitousStoreRepresentation: \.self,
                userDefaultsRepresentation: \.self
            )
        }
        
        public init(
            target: @autoclosure () -> Target,
            propertyListRepresentation: (Target) -> PropertyListRepresentation,
            ubiquitousStoreRepresentation: (Target) -> UbiquitousStoreRepresentation,
            userDefaultsRepresentation: (Target) -> UserDefaultsRepresentation
        ) {
            self.target = target()
            
            expectedPropertyListRepresentation = propertyListRepresentation(self.target)
            expectedUserDefaultsRepresentation = userDefaultsRepresentation(self.target)
            expectedUbiquitousStoreRepresentation = ubiquitousStoreRepresentation(self.target)
        }
        
        public init(
            target: Target,
            propertyListRepresentation: PropertyListRepresentation,
            ubiquitousStoreRepresentation: UbiquitousStoreRepresentation,
            userDefaultsRepresentation: UserDefaultsRepresentation
        ) {
            self.target = target
            
            expectedPropertyListRepresentation = propertyListRepresentation
            expectedUbiquitousStoreRepresentation = ubiquitousStoreRepresentation
            expectedUserDefaultsRepresentation = userDefaultsRepresentation
        }
    }
}
