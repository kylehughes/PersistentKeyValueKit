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
    /// Throws ``PersistentKeyValueConversionError/encodingFailed`` when ``to(_:)`` returns `nil`.
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
/// checked container conversion of `Proxy`.
internal protocol BuiltInProxyConversion: BuiltInContainerConversion, ProxyPersistentKeyValueRepresentationProtocol {
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

    func builtInValues(decoding propertyListArray: [Any]) throws -> [Value] {
        try Proxy.persistentKeyValueRepresentation.checkedValues(decoding: propertyListArray).map(checkedValue(for:))
    }

    func builtInDictionary(decoding propertyListDictionary: [String: Any]) throws -> [String: Value] {
        try Proxy.persistentKeyValueRepresentation.checkedDictionary(decoding: propertyListDictionary)
            .mapValues(checkedValue(for:))
    }
}
