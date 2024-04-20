//
//  ProxyablePersistentKeyValueRepresentation.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 4/20/24.
//

import Foundation

public protocol ProxyablePersistentKeyValueRepresentation<
    Value,
    ProxyRepresentation
>: PersistentKeyValueRepresentation {
    // MARK: Associated Types
    
    associatedtype ProxyRepresentation: PersistentKeyValueRepresentation
    associatedtype Value
    
    // MARK: Instance Interface
    
    var proxyRepresentation: ProxyRepresentation { get }
    
    func deserializing(_ proxy: ProxyRepresentation.Value) -> Value?
    func serializing(_ value: Value) -> ProxyRepresentation.Value
}

// MARK: - PersistentKeyValueRepresentation Extension

extension ProxyablePersistentKeyValueRepresentation {
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
