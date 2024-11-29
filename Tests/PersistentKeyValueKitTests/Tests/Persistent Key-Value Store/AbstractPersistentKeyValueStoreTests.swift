//
//  AbstractPersistentKeyValueStoreTests.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 4/28/24.
//

import Foundation
import PersistentKeyValueKit
import XCTest

#if canImport(UIKit)
import UIKit
#endif

public class AbstractPersistentKeyValueStoreTests<Target>: XCTestCase where Target: PersistentKeyValueStore {
    // MARK: Public Abstract Interface
    
    public var target: Target {
        fatalError("`target` needs to be implemented in a concrete subclass.")
    }
    
    // MARK: Public Class Interface
        
    public class var isAbstractTestCase: Bool {
        self == AbstractPersistentKeyValueStoreTests.self
    }
    
    // MARK: XCTestCase Implementation
    
    override class public var defaultTestSuite: XCTestSuite {
        guard isAbstractTestCase else {
            return super.defaultTestSuite
        }

        return XCTestSuite(name: "Empty Suite for \(Self.self)")
    }
    
    // MARK: Tests for Subscripts
    
    @MainActor
    func test_subscript_defaultValue() {
        let defaultValue = "defaultValue"
        let key = PersistentKey("key", defaultValue: defaultValue)
        
        XCTAssertEqual(target[key], defaultValue)
    }
    
    @MainActor
    func test_subscript_storedValue() {
        let defaultValue = "defaultValue"
        let storedValue = "storedValue"
        let key = PersistentKey("key", defaultValue: defaultValue)
        
        target.set(key, to: storedValue)
        
        XCTAssertEqual(target[key], storedValue)
    }
}
