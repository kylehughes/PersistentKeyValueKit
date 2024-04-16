//
//  ProxyPersistentKeyValueRepresentation.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 4/13/24.
//

import Foundation

public struct ProxyPersistentKeyValueRepresentation<Value, Proxy> where Proxy: KeyValuePersistible {
    public let deserializing: (Proxy) -> Value?
    public let proxyRepresentation: Proxy.PersistentKeyValueRepresentation
    public let serializing: (Value) -> Proxy
    
    // MARK: Public Initialization
    
    @inlinable
    public init(serializing: @escaping (Value) -> Proxy, deserializing: @escaping (Proxy) -> Value?) {
        self.serializing = serializing
        self.deserializing = deserializing
        
        proxyRepresentation = Proxy.persistentKeyValueRepresentation
    }
}

// MARK: - PersistentKeyValueRepresentation Extension

extension ProxyPersistentKeyValueRepresentation: PersistentKeyValueRepresentation {
    // MARK: Interface with User Defaults
    
    @inlinable
    public func get(_ userDefaultsKey: String, from userDefaults: UserDefaults) -> Value? {
        guard let proxyValue = proxyRepresentation.get(userDefaultsKey, from: userDefaults) else {
            return nil
        }
        
        return deserializing(proxyValue)
    }
    
    @inlinable
    public func set(_ userDefaultsKey: String, to value: Value, in userDefaults: UserDefaults) {
        proxyRepresentation.set(userDefaultsKey, to: serializing(value), in: userDefaults)
    }
    
    // MARK: Interface with Ubiquitous Key-Value Store
    
    @inlinable
    public func get(_ ubiquitousStoreKey: String, from ubiquitousStore: NSUbiquitousKeyValueStore) -> Value? {
        guard
            let proxyValue = proxyRepresentation.get(ubiquitousStoreKey, from: ubiquitousStore)
        else {
            return nil
        }
        
        return deserializing(proxyValue)
    }
    
    @inlinable
    public func set(_ ubiquitousStoreKey: String, to value: Value, in ubiquitousStore: NSUbiquitousKeyValueStore) {
        proxyRepresentation.set(ubiquitousStoreKey, to: serializing(value), in: ubiquitousStore)
    }
}
