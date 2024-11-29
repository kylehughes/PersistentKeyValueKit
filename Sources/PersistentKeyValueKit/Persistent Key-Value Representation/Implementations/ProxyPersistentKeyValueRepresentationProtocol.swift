//
//  ProxyPersistentKeyValueRepresentationProtocol.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 4/13/24.
//

import Foundation

/// A protocol for a representation of a value in a ``PersistentKeyValueStore`` that is proxied through another
/// persistible type.
///
/// This protocol is useful to build other representations that proxy a type in a specific way, like 
/// ``CodablePersistentKeyValueRepresentation`` which proxies a type through its `Codable` implementation, or
/// ``RawRepresentablePersistentKeyValueRepresentation`` which proxies a type through its `RawRepresentable`
/// implementation.
///
/// To create a one-off representation to conform a type to ``KeyValuePersistible``, one should use
/// ``ProxyPersistentKeyValueRepresentation``, which is a concrete implementation of this protocol.
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
    // MARK: Interfacing with Property List Array
    
    public func get(from propertyListArray: [Any]) -> [Value]? {
        guard let proxyValues = Proxy.persistentKeyValueRepresentation.get(from: propertyListArray) else {
            return nil
        }
        
        var originalArray: [Value] = []
        
        originalArray.reserveCapacity(proxyValues.capacity)
        
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
        
        proxyValues.reserveCapacity(values.capacity)
        
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
