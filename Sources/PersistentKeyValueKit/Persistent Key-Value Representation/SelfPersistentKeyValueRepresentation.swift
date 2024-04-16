//
//  SelfPersistentKeyValueRepresentation.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 4/13/24.
//

import Foundation

public struct SelfPersistentKeyValueRepresentation<Value> where Value: StaticPersistentKeyValueRepresentation {
    // MARK: Public Initialization
    
    @inlinable
    public init() {}
}

// MARK: - PersistentKeyValueRepresentation Extension

extension SelfPersistentKeyValueRepresentation: PersistentKeyValueRepresentation {
    // MARK: Interfacing with User Defaults
    
    @inlinable
    public func get(_ userDefaultsKey: String, from userDefaults: UserDefaults) -> Value? {
        .get(userDefaultsKey, from: userDefaults)
    }
    
    @inlinable
    public func set(_ userDefaultsKey: String, to value: Value, in userDefaults: UserDefaults) {
        Value.set(userDefaultsKey, to: value, in: userDefaults)
    }
    
    // MARK: Interfacing with Ubiquitous Key-Value Store
    
    @inlinable
    public func get(_ ubiquitousStoreKey: String, from ubiquitousStore: NSUbiquitousKeyValueStore) -> Value? {
        .get(ubiquitousStoreKey, from: ubiquitousStore)
    }
    
    @inlinable
    public func set(_ ubiquitousStoreKey: String, to value: Value, in ubiquitousStore: NSUbiquitousKeyValueStore) {
        Value.set(ubiquitousStoreKey, to: value, in: ubiquitousStore)
    }
}
