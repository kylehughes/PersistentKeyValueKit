//
//  OptionalPersistentKeyValueRepresentation.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 10/6/24.
//

import Foundation

/// A representation that wraps another ``PersistentKeyValueRepresentation`` to persist `Base.Value?`.
///
/// Non-`nil` values delegate to ``base``. Encoding `nil` returns `nil`, removing the key from a store or omitting the
/// element from a property-list collection. `Optional<Wrapped>` and the optional `PersistentKey` and
/// `PersistentDebugKey` initializers construct this representation automatically.
public struct OptionalPersistentKeyValueRepresentation<Base>
where
    Base: PersistentKeyValueRepresentation
{
    /// The underlying representation used for non-`nil` values.
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

    /// Decodes a stored object using the wrapped `base` representation.
    public func decode(storageObject: Any, format: PersistentKeyValueStorageFormat) throws -> Value {
        try base.decode(storageObject: storageObject, format: format)
    }

    /// Encodes a non-`nil` value using the wrapped `base` representation, or returns `nil` when `value` is `nil` so
    /// the key is removed from the store (or omitted from a property-list collection).
    public func encode(_ value: Value, format: PersistentKeyValueStorageFormat) throws -> Any? {
        guard let value else {
            return nil
        }
        return try base.encode(value, format: format)
    }
    
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
        
        nonOptionalValues.reserveCapacity(values.count)
        
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

// MARK: - BuiltInContainerConversion Extension

extension OptionalPersistentKeyValueRepresentation: BuiltInContainerConversion {
    // MARK: Internal Instance Interface

    func builtInPropertyListArray(encoding values: [Value]) throws -> [Any] {
        try base.checkedPropertyListArray(encoding: values.compactMap { $0 })
    }

    func builtInPropertyListDictionary(encoding values: [String: Value]) throws -> [String: Any] {
        try base.checkedPropertyListDictionary(encoding: values.compactMapValues { $0 })
    }

    func builtInValues<Element>(
        decoding propertyListArray: [Any],
        converting convert: (Value) throws -> Element
    ) throws -> [Element] {
        try base.checkedValues(decoding: propertyListArray) {
            try convert($0)
        }
    }

    func builtInDictionary(decoding propertyListDictionary: [String: Any]) throws -> [String: Value] {
        try base.checkedDictionary(decoding: propertyListDictionary).mapValues(Optional.some)
    }
}

// MARK: - BuiltInValueOmission Extension

extension OptionalPersistentKeyValueRepresentation: BuiltInValueOmission {
    // MARK: Internal Instance Interface

    /// Encodes the non-`nil` values as an ordinary write of `base` does.
    func builtInOrdinaryPropertyListArray(encoding values: [Value]) -> [Any]? {
        // Ordinary writes are a hot path, and this loop runs several times faster than an unspecialized `compactMap`.
        var nonOptionalValues: [Base.Value] = []

        nonOptionalValues.reserveCapacity(values.count)

        for value in values {
            guard let value else {
                continue
            }

            nonOptionalValues.append(value)
        }

        return base.propertyListArray(encoding: nonOptionalValues)
    }

    /// Encodes the non-`nil` values as an ordinary write of `base` does.
    ///
    /// A `base` that cannot omit values reports a failure by leaving an entry absent, so its entries are written
    /// directly. Otherwise each value is written with ``builtInOrdinaryDictionaryEntryWriter()``, which converts it
    /// through every layer of `base` before converting the next value.
    func builtInOrdinaryPropertyListDictionary(encoding values: [String: Value]) -> [String: Any]? {
        guard !(base is any BuiltInValueOmission) else {
            return propertyListDictionary(encoding: values, with: builtInOrdinaryDictionaryEntryWriter())
        }

        var objects: [String: Any] = Dictionary(minimumCapacity: values.count)

        for (key, value) in values {
            guard let value else {
                continue
            }

            base.set(key, to: value, in: &objects)

            guard objects[key] != nil else {
                return nil
            }
        }

        return objects
    }

    /// Omits a `nil` value, and writes any other value as an ordinary dictionary write of `base` does.
    func builtInOrdinaryDictionaryEntryWriter() -> OrdinaryDictionaryEntryWriter<Value> {
        let write = base.ordinaryDictionaryEntryWriter()

        return { key, value, objects in
            guard let value else {
                return true
            }

            return write(key, value, &objects)
        }
    }
}

// MARK: - Protocol Conveniences

extension PersistentKeyValueRepresentation {
    // MARK: Public Static Interface
    
    /// Returns a wrapped representation of the receiver that can represent `Value?`.
    @inlinable
    public var optionalRepresentation: OptionalPersistentKeyValueRepresentation<Self> {
        OptionalPersistentKeyValueRepresentation(self)
    }
}
