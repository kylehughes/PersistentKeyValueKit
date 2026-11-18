//
//  ProxyPersistentKeyValueRepresentationProtocol.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 4/13/24.
//

import Foundation

/// A protocol for a ``PersistentKeyValueRepresentation`` that persists `Value` by converting it to and from a
/// ``KeyValuePersistible`` `Proxy` type.
///
/// Built-in representations such as ``CodablePersistentKeyValueRepresentation``,
/// ``RawRepresentablePersistentKeyValueRepresentation``, and
/// ``LosslessStringConvertiblePersistentKeyValueRepresentation`` conform to this protocol. Use
/// ``ProxyPersistentKeyValueRepresentation`` for closure-based proxy conversions without defining a new representation
/// type.
///
/// This protocol provides default implementations of
/// ``PersistentKeyValueRepresentation/decode(storageObject:format:)``,
/// ``PersistentKeyValueRepresentation/encode(_:format:)``, and the store- and container-specific `get` and `set`
/// methods that delegate to `Proxy.persistentKeyValueRepresentation`.
/// Proxy representations defined by this package convert property-list containers through `Proxy`'s checked conversion
/// during migration and `UserDefaults.register(_:)`, whereas types defined outside this package use their
/// `get(from:)`, `set(_:to:)`, `get(_:from:)`, and `set(_:to:in:)` implementations as written (so a custom type whose
/// `Proxy` is a dictionary inherits `Dictionary`'s lenient entry decoding unless it overrides those methods).
public protocol ProxyPersistentKeyValueRepresentationProtocol<Value, Proxy>: PersistentKeyValueRepresentation {
    // MARK: Associated Types
    
    /// The persistible type used as proxy.
    associatedtype Proxy: KeyValuePersistible

    /// The type of value that is represented in a ``PersistentKeyValueStore``.
    associatedtype Value
    
    // MARK: Instance Interface
    
    /// Deserializes a value from its proxy.
    func from(_ proxy: Proxy) -> Value?

    /// Serializes a value into its proxy.
    ///
    /// The returned proxy is handed over to the package. Do not change it, or any object it contains, after returning
    /// it.
    func to(_ value: Value) -> Proxy?
}

// MARK: - PersistentKeyValueRepresentation Extension

extension ProxyPersistentKeyValueRepresentationProtocol {
    /// Decodes a stored object into `Proxy` and converts it to `Value` using ``from(_:)``.
    ///
    /// Throws ``PersistentKeyValueConversionError/invalidValue`` when ``from(_:)`` returns `nil`.
    public func decode(storageObject: Any, format: PersistentKeyValueStorageFormat) throws -> Value {
        let proxy = try Proxy.persistentKeyValueRepresentation.decode(
            storageObject: storageObject,
            format: format
        )
        guard let value = from(proxy) else {
            throw PersistentKeyValueConversionError.invalidValue
        }
        return value
    }

    /// Converts `value` into `Proxy` using ``to(_:)`` and encodes it for `format`.
    ///
    /// Returns an immutable copy of `Proxy`'s encoding after verifying that `Proxy` decodes that copy. Throws
    /// ``PersistentKeyValueConversionError/encodingFailed`` when ``to(_:)`` returns `nil` or when `Proxy`'s encoding is
    /// not a property list.
    public func encode(_ value: Value, format: PersistentKeyValueStorageFormat) throws -> Any? {
        guard let proxy = to(value) else {
            throw PersistentKeyValueConversionError.encodingFailed
        }
        return try encodeStorageRepresentation(
            Proxy.persistentKeyValueRepresentation,
            value: proxy,
            format: format
        )
    }

    // MARK: Interfacing with Property List Array
    
    public func get(from propertyListArray: [Any]) -> [Value]? {
        guard let proxyValues = Proxy.persistentKeyValueRepresentation.get(from: propertyListArray) else {
            return nil
        }
        
        var originalArray: [Value] = []
        
        originalArray.reserveCapacity(proxyValues.count)
        
        for proxyValue in proxyValues {
            guard let originalValue = from(proxyValue) else {
                return nil
            }
            
            originalArray.append(originalValue)
        }
        
        return originalArray
    }
    
    public func set(_ values: [Value], to propertyListArray: inout [Any]) {
        var proxyValues: [Proxy] = []
        
        proxyValues.reserveCapacity(values.count)
        
        for value in values {
            guard let serialization = to(value) else {
                return
            }
            
            proxyValues.append(serialization)
        }
        
        Proxy.persistentKeyValueRepresentation.set(proxyValues, to: &propertyListArray)
    }
    
    // MARK: Interfacing with Property List Dictionary
    
    @inlinable
    public func get(_ dictionaryKey: String, from propertyListDictionary: [String: Any]) -> Value? {
        guard
            let proxyValue = Proxy.persistentKeyValueRepresentation.get(dictionaryKey, from: propertyListDictionary)
        else {
            return nil
        }
        
        return from(proxyValue)
    }
    
    @inlinable
    public func set(_ dictionaryKey: String, to value: Value, in propertyListDictionary: inout [String: Any]) {
        guard let serialization = to(value) else {
            return
        }
        
        Proxy.persistentKeyValueRepresentation.set(dictionaryKey, to: serialization, in: &propertyListDictionary)
    }
    
    // MARK: Interface with User Defaults
    
    @inlinable
    public func get(_ userDefaultsKey: String, from userDefaults: UserDefaults) -> Value? {
        guard let proxyValue = Proxy.persistentKeyValueRepresentation.get(userDefaultsKey, from: userDefaults) else {
            return nil
        }
        
        return from(proxyValue)
    }
    
    @inlinable
    public func set(_ userDefaultsKey: String, to value: Value, in userDefaults: UserDefaults) {
        guard let serialization = to(value) else {
            return
        }
        
        Proxy.persistentKeyValueRepresentation.set(userDefaultsKey, to: serialization, in: userDefaults)
    }
    
    // MARK: Interface with Ubiquitous Key-Value Store
    
    @available(watchOS 9.0, *)
    @inlinable
    public func get(_ ubiquitousStoreKey: String, from ubiquitousStore: NSUbiquitousKeyValueStore) -> Value? {
        guard
            let proxyValue = Proxy.persistentKeyValueRepresentation.get(ubiquitousStoreKey, from: ubiquitousStore)
        else {
            return nil
        }
        
        return from(proxyValue)
    }
    
    @available(watchOS 9.0, *)
    @inlinable
    public func set(_ ubiquitousStoreKey: String, to value: Value, in ubiquitousStore: NSUbiquitousKeyValueStore) {
        guard let serialization = to(value) else {
            return
        }
        
        Proxy.persistentKeyValueRepresentation.set(ubiquitousStoreKey, to: serialization, in: ubiquitousStore)
    }
}

// MARK: - Built-In Proxy Conversion Definition

/// A proxy representation defined by this package, whose checked container conversion converts the proxies with the
/// checked container conversion of `Proxy`, and whose ordinary container writes omit a value whose proxy `Proxy`
/// omits.
internal protocol BuiltInProxyConversion:
    BuiltInContainerConversion,
    BuiltInValueOmission,
    ProxyPersistentKeyValueRepresentationProtocol
{
    /// Converts `value` into its proxy, throwing if it cannot be converted.
    func checkedProxy(for value: Value) throws -> Proxy

    /// Converts `proxy` into its value, throwing if it cannot be converted.
    func checkedValue(for proxy: Proxy) throws -> Value
}

// MARK: - Default Implementation

extension BuiltInProxyConversion {
    // MARK: Internal Instance Interface

    /// Converts `value` with ``ProxyPersistentKeyValueRepresentationProtocol/to(_:)``, throwing
    /// ``PersistentKeyValueConversionError/encodingFailed`` when it returns `nil`.
    func checkedProxy(for value: Value) throws -> Proxy {
        guard let proxy = to(value) else {
            throw PersistentKeyValueConversionError.encodingFailed
        }

        return proxy
    }

    /// Converts `proxy` with ``ProxyPersistentKeyValueRepresentationProtocol/from(_:)``, throwing
    /// ``PersistentKeyValueConversionError/invalidValue`` when it returns `nil`.
    func checkedValue(for proxy: Proxy) throws -> Value {
        guard let value = from(proxy) else {
            throw PersistentKeyValueConversionError.invalidValue
        }

        return value
    }

    func builtInPropertyListArray(encoding values: [Value]) throws -> [Any] {
        try Proxy.persistentKeyValueRepresentation.checkedPropertyListArray(encoding: values.map(checkedProxy(for:)))
    }

    func builtInPropertyListDictionary(encoding values: [String: Value]) throws -> [String: Any] {
        try Proxy.persistentKeyValueRepresentation.checkedPropertyListDictionary(
            encoding: values.mapValues(checkedProxy(for:))
        )
    }

    func builtInValues<Element>(
        decoding propertyListArray: [Any],
        converting convert: (Value) throws -> Element
    ) throws -> [Element] {
        try Proxy.persistentKeyValueRepresentation.checkedValues(decoding: propertyListArray) {
            try convert(checkedValue(for: $0))
        }
    }

    func builtInDictionary(decoding propertyListDictionary: [String: Any]) throws -> [String: Value] {
        try Proxy.persistentKeyValueRepresentation.checkedDictionary(decoding: propertyListDictionary)
            .mapValues(checkedValue(for:))
    }

    /// Converts each value to its proxy once, then encodes the proxies as an ordinary write of `Proxy` does.
    func builtInOrdinaryPropertyListArray(encoding values: [Value]) -> [Any]? {
        var proxies: [Proxy] = []

        proxies.reserveCapacity(values.count)

        for value in values {
            guard let proxy = to(value) else {
                return nil
            }

            proxies.append(proxy)
        }

        return Proxy.persistentKeyValueRepresentation.propertyListArray(encoding: proxies)
    }

    /// Converts each value to its proxy, then writes the proxy as an ordinary dictionary write of `Proxy` does.
    ///
    /// A `Proxy` representation that cannot omit values reports a failure by leaving an entry absent, so its entries
    /// are written directly; an entry that a `Proxy` representation defined outside this package writes, or changes
    /// while writing a later entry, also fails unless it is a property list that a store accepts. Otherwise each value
    /// is written with ``builtInOrdinaryDictionaryEntryWriter()``, which converts it through every layer of `Proxy`
    /// before converting the next value.
    func builtInOrdinaryPropertyListDictionary(encoding values: [String: Value]) -> [String: Any]? {
        let proxyRepresentation = Proxy.persistentKeyValueRepresentation

        guard !(proxyRepresentation is any BuiltInValueOmission) else {
            return propertyListDictionary(encoding: values, with: builtInOrdinaryDictionaryEntryWriter())
        }

        let validating = !(proxyRepresentation is any BuiltInPrimitiveConversion)
        var objects: [String: Any] = Dictionary(minimumCapacity: values.count)

        for (key, value) in values {
            guard let proxy = to(value) else {
                return nil
            }

            proxyRepresentation.set(key, to: proxy, in: &objects)

            guard isStorableEntry(at: key, in: &objects, validating: validating) else {
                return nil
            }
        }

        guard !validating || isStorableDictionary(&objects) else {
            return nil
        }

        return objects
    }

    /// Converts the value to its proxy, then writes the proxy as an ordinary dictionary write of `Proxy` does.
    func builtInOrdinaryDictionaryEntryWriter() -> OrdinaryDictionaryEntryWriter<Value> {
        let write = Proxy.persistentKeyValueRepresentation.ordinaryDictionaryEntryWriter()

        return OrdinaryDictionaryEntryWriter(
            requiresCompletedDictionaryValidation: write.requiresCompletedDictionaryValidation
        ) { key, value, objects in
            guard let proxy = to(value) else {
                return false
            }

            return write(key, proxy, &objects)
        }
    }
}
