//
//  OptionalPersistentKeyValueRepresentation.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 10/6/24.
//

import Foundation

/// A persistent key-value representation that can represent the `Optional` variant of another representation's
/// ``Value``. All non-optional operations are deferred to the base representation.
/// 
/// - Important: Consumers of this library should not have to interact with this type directly in happy-path scenarios.
public struct OptionalPersistentKeyValueRepresentation<Base>
where
    Base: PersistentKeyValueRepresentation
{
    public let base: Base
    
    // MARK: Public Initialization
    
    /// Creates a new optional persistent key-value representation.
    ///
    /// - Parameter base: The base persistent key-value representation that is deferred to for non-optional operations.
    @inlinable
    public init(_ base: Base) {
        self.base = base
    }
}

// MARK: - PersistentKeyValueRepresentation Extension

extension OptionalPersistentKeyValueRepresentation: PersistentKeyValueRepresentation {
    // MARK: Public Typealiases
    
    public typealias Value = Optional<Base.Value>
    
    // MARK: Interfacing with Property List Array
    
    @inlinable
    public func get(from propertyListArray: [Any]) -> [Value]? {
        guard let originalArray = base.get(from: propertyListArray) else {
            return .none
        }
        
        return originalArray
    }
    
    public func set(_ values: [Value], to propertyListArray: inout [Any]) {
        var nonOptionalValues: [Base.Value] = []
        
        nonOptionalValues.reserveCapacity(values.capacity)
        
        for value in values {
            guard let value else {
                continue
            }
            
            nonOptionalValues.append(value)
        }
        
        base.set(nonOptionalValues, to: &propertyListArray)
    }
    
    // MARK: Interfacing with Property List Dictionary
    
    @inlinable
    public func get(_ dictionaryKey: String, from propertyListDictionary: [String: Any]) -> Value? {
        guard let value = base.get(dictionaryKey, from: propertyListDictionary) else {
            return .none
        }
        
        return value
    }
    
    @inlinable
    public func set(_ dictionaryKey: String, to value: Value, in propertyListDictionary: inout [String: Any]) {
        guard let value else {
            propertyListDictionary.removeValue(forKey: dictionaryKey)
            return
        }
        
        base.set(dictionaryKey, to: value, in: &propertyListDictionary)
    }
    
    // MARK: Interfacing with User Defaults
    
    @inlinable
    public func get(_ userDefaultsKey: String, from userDefaults: UserDefaults) -> Value? {
        guard let value = base.get(userDefaultsKey, from: userDefaults) else {
            return .none
        }
        
        return value
    }
    
    @inlinable
    public func set(_ userDefaultsKey: String, to value: Value, in userDefaults: UserDefaults) {
        guard let value else {
            userDefaults.removeObject(forKey: userDefaultsKey)
            return
        }
        
        base.set(userDefaultsKey, to: value, in: userDefaults)
    }
    
    // MARK: Interfacing with Ubiquitous Key-Value Store
    
    @available(watchOS 9.0, *)
    @inlinable
    public func get(
        _ ubiquitousStoreKey: String,
        from ubiquitousStore: NSUbiquitousKeyValueStore
    ) -> Value? {
        guard let value = base.get(ubiquitousStoreKey, from: ubiquitousStore) else {
            return .none
        }
        
        return value
    }
    
    @available(watchOS 9.0, *)
    @inlinable
    public func set(_ ubiquitousStoreKey: String, to value: Value, in ubiquitousStore: NSUbiquitousKeyValueStore) {
        guard let value else {
            ubiquitousStore.removeObject(forKey: ubiquitousStoreKey)
            return
        }
        
        base.set(ubiquitousStoreKey, to: value, in: ubiquitousStore)
    }
}

// MARK: - Protocol Conveniences

extension PersistentKeyValueRepresentation {
    // MARK: Public Static Interface
    
    /// Returns a wrapped representation of the receiver that can represent ``Value?``.
    @inlinable
    public var optionalRepresentation: OptionalPersistentKeyValueRepresentation<Self> {
        OptionalPersistentKeyValueRepresentation(self)
    }
}
