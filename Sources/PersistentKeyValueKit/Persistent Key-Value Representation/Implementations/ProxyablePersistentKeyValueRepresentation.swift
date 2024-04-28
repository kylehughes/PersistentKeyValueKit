//
//  ProxyablePersistentKeyValueRepresentation.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 4/13/24.
//

import Foundation

public protocol ProxyablePersistentKeyValueRepresentation<Value, Proxy>: PersistentKeyValueRepresentation {
    // MARK: Associated Types
    
    associatedtype Proxy: KeyValuePersistible
    associatedtype Value
    
    // MARK: Instance Interface
    
    func deserializing(_ proxy: Proxy) -> Value?
    func serializing(_ value: Value) -> Proxy?
}

// MARK: - PersistentKeyValueRepresentation Extension

extension ProxyablePersistentKeyValueRepresentation {
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
