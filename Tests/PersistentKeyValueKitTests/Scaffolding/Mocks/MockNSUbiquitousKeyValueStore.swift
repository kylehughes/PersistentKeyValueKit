//
//  MockNSUbiquitousKeyValueStore.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 4/28/24.
//

import Foundation

@testable import PersistentKeyValueKit

/// A subclass of `NSUbiquitousKeyValueStore` that overrides the implementations of all initializers, functions,
/// and symbols that are used by this framework.
///
/// We prefer to test actual implementations but `NSUbiquitousKeyValueStore` requires iCloud entitlements and we
/// cannot instrument that for unit tests. We make a best-effort attempt to reflect the important details of the
/// underlying implementation.
@available(watchOS 9.0, *)
public class MockUbiquitousKeyValueStore: NSUbiquitousKeyValueStore {
    public var storage: [String: Any]
    public var synchronizeReturnValue: Bool
    
    // MARK: Public Initialization
    
    override public init() {
        storage = [:]
        synchronizeReturnValue = true
    }
    
    // MARK: Constants
    
    nonisolated(unsafe) public static let mockDefault = MockUbiquitousKeyValueStore()
    
    public override class var `default`: NSUbiquitousKeyValueStore {
        mockDefault
    }
    
    // MARK: Getting Values

    public override func object(forKey aKey: String) -> Any? {
        storage[aKey]
    }

    public override func string(forKey aKey: String) -> String? {
        storage[aKey] as? String
    }

    public override func array(forKey aKey: String) -> [Any]? {
        storage[aKey] as? [Any]
    }

    public override func dictionary(forKey aKey: String) -> [String: Any]? {
        storage[aKey] as? [String: Any]
    }

    public override func data(forKey aKey: String) -> Data? {
        storage[aKey] as? Data
    }

    public override func longLong(forKey aKey: String) -> Int64 {
        storage[aKey] as? Int64 ?? 0
    }

    public override func double(forKey aKey: String) -> Double {
        storage[aKey] as? Double ?? 0.0
    }

    public override func bool(forKey aKey: String) -> Bool {
        storage[aKey] as? Bool ?? false
    }
    
    // MARK: Setting Values
    
    public override func set(_ anObject: Any?, forKey aKey: String) {
        storage[aKey] = anObject
        
        Self.postInternalChangeNotification(for: aKey, from: self)
    }
    
    public override func set(_ aString: String?, forKey aKey: String) {
        storage[aKey] = aString
        
        Self.postInternalChangeNotification(for: aKey, from: self)
    }

    public override func set(_ aData: Data?, forKey aKey: String) {
        storage[aKey] = aData
        
        Self.postInternalChangeNotification(for: aKey, from: self)
    }

    public override func set(_ anArray: [Any]?, forKey aKey: String) {
        storage[aKey] = anArray
        
        Self.postInternalChangeNotification(for: aKey, from: self)
    }

    public override func set(_ aDictionary: [String: Any]?, forKey aKey: String) {
        storage[aKey] = aDictionary
        
        Self.postInternalChangeNotification(for: aKey, from: self)
    }

    public override func set(_ value: Int64, forKey aKey: String) {
        storage[aKey] = value
        
        Self.postInternalChangeNotification(for: aKey, from: self)
    }

    public override func set(_ value: Double, forKey aKey: String) {
        storage[aKey] = value
        
        Self.postInternalChangeNotification(for: aKey, from: self)
    }

    public override func set(_ value: Bool, forKey aKey: String) {
        storage[aKey] = value
        
        Self.postInternalChangeNotification(for: aKey, from: self)
    }
    
    // MARK: Explicitly Synchronizing In-Memory Key-Value Data to Disk

    public override func synchronize() -> Bool {
        synchronizeReturnValue
    }
    
    // MARK: Removing Keys
    
    public override func removeObject(forKey aKey: String) {
        storage.removeValue(forKey: aKey)
        
        Self.postInternalChangeNotification(for: aKey, from: self)
    }
    
    // MARK: Retrieving the Current Keys and Values

    public override var dictionaryRepresentation: [String: Any] {
        storage
    }
}
