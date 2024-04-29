//
//  DirectPersistentKeyValueRepresentation.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 4/13/24.
//

import Foundation

/// A representation of a value in a ``PersistentKeyValueStore`` that is itself a persistible type and defines
/// explicitly how to interface with `UserDefaults` and `NSUbiquitousKeyValueStore`.
public struct DirectPersistentKeyValueRepresentation<Value>
where
    Value: DirectPersistentKeyValueRepresentationProtocol
{
    // MARK: Public Initialization
    
    /// Creates a new representation.
    @inlinable
    public init() {}
}

// MARK: - PersistentKeyValueRepresentation Extension

extension DirectPersistentKeyValueRepresentation: PersistentKeyValueRepresentation {
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
