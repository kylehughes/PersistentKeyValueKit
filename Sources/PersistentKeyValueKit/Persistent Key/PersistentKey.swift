//
//  PersistentKey.swift
//  KeyValueKit
//
//  Created by Kyle Hughes on 3/28/22.
//

import Foundation

/// A key for a value in a ``PersistentKeyValueStore``.
///
/// It is encouraged to use static accessors for keys because our APIs are designed for static member lookup.
/// 
/// e.g.
///
/// ```swift
/// extension PersistentKeyProtocol where Self == PersistentKey<Date?> {
///     static var dateAskedForAppStoreRating: Self {
///         Self(id: "DateAskedForAppStoreRating", defaultValue: nil)
///     }
/// }
/// ```
public struct PersistentKey<Value>: Identifiable where Value: KeyValuePersistible {
    public let defaultValue: Value
    public let id: String
    
    // MARK: Public Initialization
    
    @inlinable
    public init(id: String, defaultValue: Value) {
        self.id = id
        self.defaultValue = defaultValue
    }
}

// MARK: - Conditional Codable Extension

extension PersistentKey: Codable where Value: Codable {
    // NO-OP
}

// MARK: - Conditional Equatable Extension

extension PersistentKey: Equatable where Value: Equatable {
    // NO-OP
}

// MARK: - Conditional Hashable Extension

extension PersistentKey: Hashable where Value: Hashable {
    // NO-OP
}

// MARK: - PersistentKeyProtocol Extension

extension PersistentKey: PersistentKeyProtocol {
    // MARK: Public Instance Interface

    @inlinable
    public func get(from userDefaults: UserDefaults) -> Value {
        .deserialize(for: self, from: Value.extract(self, from: userDefaults))
    }
    
    @inlinable
    public func remove(from userDefaults: UserDefaults) {
        userDefaults.removeObject(forKey: id)
    }
    
    @inlinable
    public func set(to newValue: Value, in userDefaults: UserDefaults) {
        newValue.store(as: id, in: userDefaults)
    }
    
    #if !os(watchOS)
    
    @inlinable
    public func get(from ubiquitousStore: NSUbiquitousKeyValueStore) -> Value {
        .deserialize(for: self, from: Value.extract(self, from: ubiquitousStore))
    }
    
    @inlinable
    public func remove(from ubiquitousStore: NSUbiquitousKeyValueStore) {
        ubiquitousStore.removeObject(forKey: id)
    }
    
    @inlinable
    public func set(to newValue: Value, in ubiquitousStore: NSUbiquitousKeyValueStore) {
        newValue.store(as: id, in: ubiquitousStore)
    }
    
    #endif
}
