//
//  AbstractPersistentKeyValueStoreTypeTests.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 11/3/24.
//

import Foundation
import PersistentKeyValueKit
import XCTest

/// - Important: These tests are technically supersets of various other scoped-down tests and contribute little to
///   unique code coverage. However, these tests are end-to-end and involve all of the major pieces of the framework:
///   ``KeyValuePersistible``, ``PersistentKeyProtocol``, and ``PersistentKeyValueStore``. Where the abstract tests for
///   those individual protocols are better for "test-driven development" during implementation, these tests help
///   build confidence in the whole system. That is why we are so exhaustive in testing every permutation of supported
///   type and store: we have to get this right, and while the scope is large, it is small enough for us to be
///   exhaustive.
public class AbstractPersistentKeyValueStoreTypeTests<Target, Store>: XCTestCase
where
    Target: Equatable & KeyValuePersistible & Sendable,
    Store: PersistentKeyValueStore
{
    // MARK: Public Abstract Interface
    
    public var testValues: [Target] {
        fatalError("`testValues` needs to be implemented in a concrete subclass.")
    }
    
    public var store: Store {
        fatalError("`store` needs to be implemented in a concrete subclass.")
    }
    
    // MARK: Public Class Interface
    
    public class var isAbstractTestCase: Bool {
        self == AbstractPersistentKeyValueStoreTypeTests.self
    }
    
    // MARK: XCTestCase Implementation
    
    override public class var defaultTestSuite: XCTestSuite {
        guard isAbstractTestCase else {
            return super.defaultTestSuite
        }
        
        return XCTestSuite(name: "Empty Suite for \(Self.self)")
    }
    
    override public func setUp() {
        guard !testValues.isEmpty else {
            XCTFail("Test values array cannot be empty")
            return
        }
    }
    
    // MARK: Default Value Tests
        
    @MainActor
    func test_default_nonoptional() {
        for (index, defaultValue) in zip(testValues.indices, testValues) {
            let key = PersistentKey<Target>("\(index)", defaultValue: defaultValue)
            
            XCTAssertEqual(store.get(key), defaultValue)
        }
    }
    
    @MainActor
    func test_default_optional_withValue() {
        for (index, defaultValue) in zip(testValues.indices, testValues) {
            let key = PersistentKey<Target?>("\(index)", defaultValue: defaultValue)
            
            XCTAssertEqual(store.get(key), defaultValue)
        }
    }
    
    @MainActor
    func test_default_optional_nil() {
        let key = PersistentKey<Target?>("nil", defaultValue: nil)
        
        XCTAssertEqual(store.get(key), nil)
    }
    
    @MainActor
    func test_array_defaultValue_empty() {
        let emptyKey = PersistentKey<[Target]>("empty", defaultValue: [])
        
        XCTAssertEqual(store.get(emptyKey), [])
    }

    @MainActor
    func test_array_defaultValue_withValues() {
        let key = PersistentKey<[Target]>("full", defaultValue: testValues)
        
        XCTAssertEqual(store.get(key), testValues)
    }

    @MainActor
    func test_arrayOptional_defaultValue_empty() {
        let emptyKey = PersistentKey<[Target?]>("empty", defaultValue: [])
        
        XCTAssertEqual(store.get(emptyKey), [])
    }

    @MainActor
    func test_arrayOptional_defaultValue_withValues() {
        let allValues = testValues.map { Optional($0) } + [nil]
        
        let key = PersistentKey<[Target?]>("full", defaultValue: allValues)
        
        XCTAssertEqual(store.get(key), allValues)
    }

    @MainActor
    func test_optionalArray_defaultValue_nil() {
        let nilKey = PersistentKey<[Target]?>("nil", defaultValue: nil)
        
        XCTAssertEqual(store.get(nilKey), nil)
    }

    @MainActor
    func test_optionalArray_defaultValue_empty() {
        let emptyKey = PersistentKey<[Target]?>("empty", defaultValue: [])
        
        XCTAssertEqual(store.get(emptyKey), [])
    }

    @MainActor
    func test_optionalArray_defaultValue_withValues() {
        let key = PersistentKey<[Target]?>("full", defaultValue: testValues)
        
        XCTAssertEqual(store.get(key), testValues)
    }

    @MainActor
    func test_optionalArrayOptional_defaultValue_nil() {
        let nilKey = PersistentKey<[Target?]?>("nil", defaultValue: nil)
        
        XCTAssertEqual(store.get(nilKey), nil)
    }

    @MainActor
    func test_optionalArrayOptional_defaultValue_empty() {
        let emptyKey = PersistentKey<[Target?]?>("empty", defaultValue: [])
        
        XCTAssertEqual(store.get(emptyKey), [])
    }

    @MainActor
    func test_optionalArrayOptional_defaultValue_withValues() {
        let allValues = testValues.map { Optional($0) } + [nil]
        
        let key = PersistentKey<[Target?]?>("full", defaultValue: allValues)
        
        XCTAssertEqual(store.get(key), allValues)
    }

    @MainActor
    func test_dictionary_defaultValue_empty() {
        let emptyKey = PersistentKey<[String: Target]>("empty", defaultValue: [:])
        
        XCTAssertEqual(store.get(emptyKey), [:])
    }

    @MainActor
    func test_dictionary_defaultValue_withValues() {
        let fullDict = Dictionary(
            uniqueKeysWithValues: zip(testValues.indices, testValues).map { index, value in
                ("key\(index)", value)
            }
        )
        
        let key = PersistentKey<[String: Target]>("full", defaultValue: fullDict)
        
        XCTAssertEqual(store.get(key), fullDict)
    }

    @MainActor
    func test_dictionaryOptional_defaultValue_empty() {
        let emptyKey = PersistentKey<[String: Target?]>("empty", defaultValue: [:])
        
        XCTAssertEqual(store.get(emptyKey), [:])
    }

    @MainActor
    func test_dictionaryOptional_defaultValue_withValues() {
        let allValues = testValues.map { Optional($0) } + [nil]
        
        let fullDict = Dictionary(
            uniqueKeysWithValues: zip(allValues.indices, allValues).map { index, value in
                ("key\(index)", value)
            }
        )
        
        let key = PersistentKey<[String: Target?]>("full", defaultValue: fullDict)
        
        XCTAssertEqual(store.get(key), fullDict)
    }

    @MainActor
    func test_optionalDictionary_defaultValue_nil() {
        let nilKey = PersistentKey<[String: Target]?>("nil", defaultValue: nil)
        
        XCTAssertEqual(store.get(nilKey), nil)
    }

    @MainActor
    func test_optionalDictionary_defaultValue_empty() {
        let emptyKey = PersistentKey<[String: Target]?>("empty", defaultValue: [:])
        
        XCTAssertEqual(store.get(emptyKey), [:])
    }

    @MainActor
    func test_optionalDictionary_defaultValue_withValues() {
        let fullDict = Dictionary(
            uniqueKeysWithValues: zip(testValues.indices, testValues).map { index, value in
                ("key\(index)", value)
            }
        )
        
        let key = PersistentKey<[String: Target]?>("full", defaultValue: fullDict)
        
        XCTAssertEqual(store.get(key), fullDict)
    }

    @MainActor
    func test_optionalDictionaryOptional_defaultValue_nil() {
        let nilKey = PersistentKey<[String: Target?]?>("nil", defaultValue: nil)
        
        XCTAssertEqual(store.get(nilKey), nil)
    }

    @MainActor
    func test_optionalDictionaryOptional_defaultValue_empty() {
        let emptyKey = PersistentKey<[String: Target?]?>("empty", defaultValue: [:])
        
        XCTAssertEqual(store.get(emptyKey), [:])
    }

    @MainActor
    func test_optionalDictionaryOptional_defaultValue_withValues() {
        let allValues = testValues.map { Optional($0) } + [nil]
        
        let fullDict = Dictionary(
            uniqueKeysWithValues: zip(allValues.indices, allValues).map { index, value in
                ("key\(index)", value)
            }
        )
        
        let key = PersistentKey<[String: Target?]?>("full", defaultValue: fullDict)
        
        XCTAssertEqual(store.get(key), fullDict)
    }
    
    // MARK: End-to-End Tests
    
    @MainActor
    func test_endToEnd_nonoptional() {
        for (defaultIndex, defaultValue) in zip(testValues.indices, testValues) {
            for (storedIndex, storedValue) in zip(testValues.indices, testValues) where storedValue != defaultValue {
                let key = PersistentKey<Target>("\(defaultIndex):\(storedIndex)", defaultValue: defaultValue)
                
                XCTAssertEqual(store.get(key), defaultValue)
                
                store.set(key, to: storedValue)
                
                XCTAssertEqual(store.get(key), storedValue)
            }
        }
    }
    
    @MainActor
    func test_endToEnd_array() {
        for defaultSize in 1 ... testValues.count {
            let defaultArray = Array(testValues.prefix(defaultSize))
            
            for storedSize in 1 ... testValues.count {
                let storedArray = Array(testValues.suffix(storedSize))
                
                let key = PersistentKey<[Target]>("\(defaultSize):\(storedSize)", defaultValue: defaultArray)
                
                XCTAssertEqual(store.get(key), defaultArray)
                
                store.set(key, to: storedArray)
                
                XCTAssertEqual(store.get(key), storedArray)
            }
        }
    }
    
    @MainActor
    func test_endToEnd_array_optional() {
        let allValues = testValues.map { Optional($0) } + [nil]
        
        for defaultSize in 1 ... allValues.count {
            let defaultArray = Array(allValues.prefix(defaultSize))
            
            for storedSize in 1 ... allValues.count {
                let storedArray = Array(allValues.suffix(storedSize))
                
                let key = PersistentKey<[Target?]>("\(defaultSize):\(storedSize)", defaultValue: defaultArray)
                
                XCTAssertEqual(store.get(key), defaultArray)
                
                store.set(key, to: storedArray)
                
                XCTAssertEqual(store.get(key), storedArray.compactMap(\.self))
            }
        }
    }
    
    @MainActor
    func test_endToEnd_optional_from() {
        for (index, storedValue) in zip(testValues.indices, testValues) {
            let key = PersistentKey<Target?>("\(index)", defaultValue: nil)
            
            XCTAssertEqual(store.get(key), nil)
            
            store.set(key, to: storedValue)
            
            XCTAssertEqual(store.get(key), storedValue)
        }
    }
    
    @MainActor
    func test_endToEnd_optional_array_from() {
        for size in 1 ... testValues.count {
            let storedArray = Array(testValues.prefix(size))
            
            let key = PersistentKey<[Target]?>("\(size)", defaultValue: nil)
            
            XCTAssertEqual(store.get(key), nil)
            
            store.set(key, to: storedArray)
            
            XCTAssertEqual(store.get(key), storedArray)
        }
    }
    
    @MainActor
    func test_endToEnd_optional_array_optional_from() {
        let allValues = testValues.map { Optional($0) } + [nil]
        
        for size in 1 ... allValues.count {
            let storedArray = Array(allValues.prefix(size))
            
            let key = PersistentKey<[Target?]?>("\(size)", defaultValue: nil)
            
            XCTAssertEqual(store.get(key), nil)
            
            store.set(key, to: storedArray)
            
            XCTAssertEqual(store.get(key), storedArray.compactMap(\.self))
        }
    }
    
    @MainActor
    func test_endToEnd_optional_to() {
        for (index, initialValue) in zip(testValues.indices, testValues) {
            let key = PersistentKey<Target?>("\(index)", defaultValue: nil)
            
            XCTAssertEqual(store.get(key), nil)
            
            store.set(key, to: initialValue)
            
            XCTAssertEqual(store.get(key), initialValue)
            
            store.set(key, to: nil)
            
            XCTAssertEqual(store.get(key), nil)
        }
    }
    
    @MainActor
    func test_endToEnd_optional_array_to() {
        for size in 1 ... testValues.count {
            let initialArray = Array(testValues.prefix(size))
            
            let key = PersistentKey<[Target]?>("\(size)", defaultValue: nil)
            
            XCTAssertEqual(store.get(key), nil)
            
            store.set(key, to: initialArray)
            
            XCTAssertEqual(store.get(key), initialArray)
            
            store.set(key, to: nil)
            
            XCTAssertEqual(store.get(key), nil)
        }
    }
    
    @MainActor
    func test_endToEnd_optional_array_optional_to() {
        let allValues = testValues.map { Optional($0) } + [nil]
        
        for size in 1 ... allValues.count {
            let initialArray = Array(allValues.prefix(size))
            
            let key = PersistentKey<[Target?]?>("\(size)", defaultValue: nil)
            
            XCTAssertEqual(store.get(key), nil)
            
            store.set(key, to: initialArray)
            
            XCTAssertEqual(store.get(key), initialArray.compactMap(\.self))
            
            store.set(key, to: nil)
            
            XCTAssertEqual(store.get(key), nil)
        }
    }
    
    @MainActor
    func test_endToEnd_dictionary() {
        for defaultSize in 1 ... testValues.count {
            let defaultDict = Dictionary(
                uniqueKeysWithValues: testValues.prefix(defaultSize).enumerated().map { index, value in
                    ("key\(index)", value)
                }
            )
            
            for storedSize in 1 ... testValues.count {
                let storedDict = Dictionary(
                    uniqueKeysWithValues: testValues.suffix(storedSize).enumerated().map { index, value in
                        ("stored\(index)", value)
                    }
                )
                
                let key = PersistentKey<[String: Target]>("\(defaultSize):\(storedSize)", defaultValue: defaultDict)
                
                XCTAssertEqual(store.get(key), defaultDict)
                
                store.set(key, to: storedDict)
                
                XCTAssertEqual(store.get(key), storedDict)
            }
        }
    }

    @MainActor
    func test_endToEnd_dictionary_optional() {
        let allValues = testValues.map { Optional($0) } + [nil]
        
        for defaultSize in 1 ... allValues.count {
            let defaultDict = Dictionary(
                uniqueKeysWithValues: allValues.prefix(defaultSize).enumerated().map { index, value in
                    ("key\(index)", value)
                }
            )
            
            for storedSize in 1...allValues.count {
                let storedDict = Dictionary(
                    uniqueKeysWithValues: allValues.suffix(storedSize).enumerated().map { index, value in
                        ("stored\(index)", value)
                    }
                )
                
                let key = PersistentKey<[String: Target?]>("\(defaultSize):\(storedSize)", defaultValue: defaultDict)
                
                XCTAssertEqual(store.get(key), defaultDict)
                
                store.set(key, to: storedDict)
                                
                XCTAssertEqual(store.get(key), storedDict.compactMapValues(\.self))
            }
        }
    }

    @MainActor
    func test_endToEnd_optional_dictionary_from() {
        for size in 1 ... testValues.count {
            let storedDict = Dictionary(
                uniqueKeysWithValues: testValues.prefix(size).enumerated().map { index, value in
                    ("key\(index)", value)
                }
            )
            
            let key = PersistentKey<[String: Target]?>("\(size)", defaultValue: nil)
            
            XCTAssertEqual(store.get(key), nil)
            
            store.set(key, to: storedDict)
            
            XCTAssertEqual(store.get(key), storedDict)
        }
    }

    @MainActor
    func test_endToEnd_optional_dictionary_optional_from() {
        let allValues = testValues.map { Optional($0) } + [nil]
        
        for size in 1 ... allValues.count {
            let storedDict = Dictionary(
                uniqueKeysWithValues: allValues.prefix(size).enumerated().map { index, value in
                    ("key\(index)", value)
                }
            )
            
            let key = PersistentKey<[String: Target?]?>("\(size)", defaultValue: nil)
            
            XCTAssertEqual(store.get(key), nil)
            
            store.set(key, to: storedDict)
            
            XCTAssertEqual(store.get(key), storedDict.compactMapValues(\.self))
        }
    }

    @MainActor
    func test_endToEnd_optional_dictionary_to() {
        for size in 1 ... testValues.count {
            let initialDict = Dictionary(
                uniqueKeysWithValues: testValues.prefix(size).enumerated().map { index, value in
                    ("key\(index)", value)
                }
            )
            
            let key = PersistentKey<[String: Target]?>("\(size)", defaultValue: nil)
            
            XCTAssertEqual(store.get(key), nil)
            
            store.set(key, to: initialDict)
            
            XCTAssertEqual(store.get(key), initialDict)
            
            store.set(key, to: nil)
            
            XCTAssertEqual(store.get(key), nil)
        }
    }

    @MainActor
    func test_endToEnd_optional_dictionary_optional_to() {
        let allValues = testValues.map { Optional($0) } + [nil]
        
        for size in 1 ... allValues.count {
            let initialDict = Dictionary(
                uniqueKeysWithValues: allValues.prefix(size).enumerated().map { index, value in
                    ("key\(index)", value)
                }
            )
            
            let key = PersistentKey<[String: Target?]?>("\(size)", defaultValue: nil)
            
            XCTAssertEqual(store.get(key), nil)
            
            store.set(key, to: initialDict)
            
            XCTAssertEqual(store.get(key), initialDict.compactMapValues(\.self))
            
            store.set(key, to: nil)
            
            XCTAssertEqual(store.get(key), nil)
        }
    }
}
