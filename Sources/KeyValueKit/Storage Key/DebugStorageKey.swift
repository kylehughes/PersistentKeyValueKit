//
//  DebugStorageKey.swift
//  KeyValueKit
//
//  Created by Kyle Hughes on 4/9/22.
//

import Foundation

public struct DebugStorageKey<Value>: Identifiable, StorageKeyProtocol where Value: KeyValueStorable {
    public let defaultValue: Value
    public let id: String
    
    // MARK: Public Initialization
    
    @inlinable
    public init(id: String, defaultValue: Value) {
        self.id = id
        self.defaultValue = defaultValue
    }
}

// MARK: - StorageKeyProtocol Extension

extension DebugStorageKey {
    // MARK: Public Instance Interface
    
    @inlinable
    public func get(from userDefaults: UserDefaults) -> Value {
        #if DEBUG
        .deserialize(for: self, from: Value.extract(self, from: userDefaults))
        #else
        defaultValue
        #endif
    }
    
    @inlinable
    public func set(to newValue: Value, in userDefaults: UserDefaults) {
        #if DEBUG
        newValue.store(as: id, in: userDefaults)
        #else
        // NO-OP
        #endif
    }
    
    @inlinable
    public func remove(from userDefaults: UserDefaults) {
        #if DEBUG
        userDefaults.removeObject(forKey: id)
        #else
        // NO-OP
        #endif
    }
    
    #if !os(watchOS)
    
    @inlinable
    public func get(from ubiquitousStore: NSUbiquitousKeyValueStore) -> Value {
        #if DEBUG
        .deserialize(for: self, from: Value.extract(self, from: ubiquitousStore))
        #else
        defaultValue
        #endif
    }
    
    @inlinable
    public func set(to newValue: Value, in ubiquitousStore: NSUbiquitousKeyValueStore) {
        #if DEBUG
        newValue.store(as: id, in: ubiquitousStore)
        #else
        // NO-OP
        #endif
    }
    
    @inlinable
    public func remove(from ubiquitousStore: NSUbiquitousKeyValueStore) {
        #if DEBUG
        ubiquitousStore.removeObject(forKey: id)
        #else
        // NO-OP
        #endif
    }
    
    #endif
}
