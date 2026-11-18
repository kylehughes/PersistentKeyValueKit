//
//  PrimitivePersistentKeyValueRepresentation.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 4/13/24.
//

import Foundation

/// A representation that delegates conversion and store access to a ``PrimitiveKeyValuePersistible`` type.
///
/// Built-in primitive types (`Bool`, `Int`, `Float`, `Double`, `String`, `Data`, `URL`, `Array`, and `Dictionary`) use
/// this representation as their default ``KeyValuePersistible/persistentKeyValueRepresentation``.
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
    // MARK: Checked Conversion

    public func decode(storageObject: Any, format: PersistentKeyValueStorageFormat) throws -> Value {
        try Value.decode(storageObject: storageObject, format: format)
    }

    public func encode(_ value: Value, format: PersistentKeyValueStorageFormat) throws -> Any? {
        try value.encode(format: format)
    }

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

// MARK: - BuiltInContainerConversion Extension

extension PrimitivePersistentKeyValueRepresentation: BuiltInContainerConversion where Value: BuiltInContainerPrimitive {
    // MARK: Internal Instance Interface

    func builtInPropertyListArray(encoding values: [Value]) throws -> [Any] {
        try values.compactMap {
            try $0.encode(format: .propertyList)
        }
    }

    func builtInPropertyListDictionary(encoding values: [String: Value]) throws -> [String: Any] {
        try values.compactMapValues {
            try $0.encode(format: .propertyList)
        }
    }

    func builtInValues<Element>(
        decoding propertyListArray: [Any],
        converting convert: (Value) throws -> Element
    ) throws -> [Element] {
        try propertyListArray.map {
            try convert(Value.decode(storageObject: $0, format: .propertyList))
        }
    }

    func builtInDictionary(decoding propertyListDictionary: [String: Any]) throws -> [String: Value] {
        try propertyListDictionary.mapValues {
            try Value.decode(storageObject: $0, format: .propertyList)
        }
    }
}

// MARK: - BuiltInScalarConversion Extension

extension PrimitivePersistentKeyValueRepresentation: BuiltInScalarConversion where Value: BuiltInScalarPrimitive {}

// MARK: - Built-In Container Primitive Definition

/// A built-in primitive container, `Array` or `Dictionary`, whose checked conversion as an element decodes and
/// encodes each element itself instead of using its ordinary container methods.
///
/// Built-in scalar primitives conform to ``BuiltInScalarPrimitive`` instead: their container methods cast or convert
/// each element exactly as their checked conversion does, so checked conversion calls those methods.
internal protocol BuiltInContainerPrimitive: PrimitiveKeyValuePersistible {}

// MARK: - Built-In Scalar Primitive Definition

/// A built-in scalar primitive, such as `Int` or `URL`, whose container methods cast or convert each element exactly
/// as its checked conversion does.
internal protocol BuiltInScalarPrimitive: PrimitiveKeyValuePersistible {}
