//
//  PrimitivePersistentKeyValueRepresentation.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 4/13/24.
//

import Foundation

/// A representation of a value in a ``PersistentKeyValueStore`` that is itself a persistible type and defines
/// explicitly how to interface with `UserDefaults` and `NSUbiquitousKeyValueStore`.
///
/// ``Value`` is required to conform to ``PrimitiveKeyValuePersistible``. All applicable standard library & Foundation
/// types already conform. It is unlikely that you need to use this representation, unless you have built an
/// especially-custom representation for your custom type and made it conform to ``PrimitiveKeyValuePersistible``.
///
/// - SeeAlso: ``PrimitiveKeyValuePersistible``
public struct PrimitivePersistentKeyValueRepresentation<Value>
where
    Value: PrimitiveKeyValuePersistible
{
    // MARK: Public Initialization
    
    /// Creates a new representation.
    @inlinable
    public init() {}
}

// MARK: - PersistentKeyValueRepresentation Extension

extension PrimitivePersistentKeyValueRepresentation: PersistentKeyValueRepresentation {
    // MARK: Interfacing with Property List Array
    
    @inlinable
    public func get(from propertyListArray: [Any]) -> [Value]? {
        Value.get(from: propertyListArray)
    }
    
    @inlinable
    public func set(_ values: [Value], to propertyListArray: inout [Any]) {
        Value.set(values, to: &propertyListArray)
    }
    
    // MARK: Interfacing with Property List Dictionary
    
    @inlinable
    public func get(_ dictionaryKey: String, from propertyListDictionary: [String: Any]) -> Value? {
        Value.get(dictionaryKey, from: propertyListDictionary)
    }
    
    @inlinable
    public func set(_ dictionaryKey: String, to value: Value, in propertyListDictionary: inout [String: Any]) {
        Value.set(dictionaryKey, to: value, in: &propertyListDictionary)
    }
    
    // MARK: Interfacing with User Defaults
    
    @inlinable
    public func get(_ userDefaultsKey: String, from userDefaults: UserDefaults) -> Value? {
        Value.get(userDefaultsKey, from: userDefaults)
    }
    
    @inlinable
    public func set(_ userDefaultsKey: String, to value: Value, in userDefaults: UserDefaults) {
        Value.set(userDefaultsKey, to: value, in: userDefaults)
    }
    
    // MARK: Interfacing with Ubiquitous Key-Value Store
    
    @available(watchOS 9.0, *)
    @inlinable
    public func get(_ ubiquitousStoreKey: String, from ubiquitousStore: NSUbiquitousKeyValueStore) -> Value? {
        Value.get(ubiquitousStoreKey, from: ubiquitousStore)
    }
    
    @available(watchOS 9.0, *)
    @inlinable
    public func set(_ ubiquitousStoreKey: String, to value: Value, in ubiquitousStore: NSUbiquitousKeyValueStore) {
        Value.set(ubiquitousStoreKey, to: value, in: ubiquitousStore)
    }
}
