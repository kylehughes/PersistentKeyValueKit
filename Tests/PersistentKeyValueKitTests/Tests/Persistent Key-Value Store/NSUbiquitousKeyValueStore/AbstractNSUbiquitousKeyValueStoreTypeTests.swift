//
//  AbstractNSUbiquitousKeyValueStoreTypeTests.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 11/17/24.
//

import Foundation
import PersistentKeyValueKit
import XCTest

@available(watchOS 9.0, *)
public class AbstractNSUbiquitousKeyValueStoreTypeTests<Target>:
    AbstractPersistentKeyValueStoreTypeTests<Target, NSUbiquitousKeyValueStore>
where
    Target: Equatable & KeyValuePersistible & Sendable
{
    private let _store = MockUbiquitousKeyValueStore()
    
    // MARK: AbstractPersistentKeyValueStoreTypeTests Implementation
    
    override public var store: NSUbiquitousKeyValueStore {
        _store
    }
    
    // MARK: XCTestCase Implementation
    
    override public func tearDown() {
        store.dictionaryRepresentation.keys.forEach(store.removeObject)
    }
    
    // MARK: Public Class Interface
    
    override public class var isAbstractTestCase: Bool {
        self == AbstractNSUbiquitousKeyValueStoreTypeTests.self
    }
}
