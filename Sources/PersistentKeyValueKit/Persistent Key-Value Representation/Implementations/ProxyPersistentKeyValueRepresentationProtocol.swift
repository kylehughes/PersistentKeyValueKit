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
    func deserializing(_ proxy: Proxy) -> Value?

    /// Serializes a value into its proxy.
    func serializing(_ value: Value) -> Proxy?
}

// MARK: - PersistentKeyValueRepresentation Extension

extension ProxyPersistentKeyValueRepresentationProtocol {
    // MARK: Interface with User Defaults
    
    @inlinable
    public func get(_ userDefaultsKey: String, from userDefaults: UserDefaults) -> Value? {
        guard let proxyValue = Proxy.persistentKeyValueRepresentation.get(userDefaultsKey, from: userDefaults) else {
            return nil
        }
        
        return deserializing(proxyValue)
    }
    
    @inlinable
    public func set(_ userDefaultsKey: String, to value: Value, in userDefaults: UserDefaults) {
        guard let serialization = serializing(value) else {
            return
        }
        
        Proxy.persistentKeyValueRepresentation.set(userDefaultsKey, to: serialization, in: userDefaults)
    }
    
    // MARK: Interface with Ubiquitous Key-Value Store
    
    @inlinable
    public func get(_ ubiquitousStoreKey: String, from ubiquitousStore: NSUbiquitousKeyValueStore) -> Value? {
        guard
            let proxyValue = Proxy.persistentKeyValueRepresentation.get(ubiquitousStoreKey, from: ubiquitousStore)
        else {
            return nil
        }
        
        return deserializing(proxyValue)
    }
    
    @inlinable
    public func set(_ ubiquitousStoreKey: String, to value: Value, in ubiquitousStore: NSUbiquitousKeyValueStore) {
        guard let serialization = serializing(value) else {
            return
        }
        
        Proxy.persistentKeyValueRepresentation.set(ubiquitousStoreKey, to: serialization, in: ubiquitousStore)
    }
}
