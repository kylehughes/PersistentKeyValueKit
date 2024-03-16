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
/// …
/// userDefaults.get(.dateAskedForAppStoreRating)
/// ```
public struct PersistentKey<Value>: Identifiable where Value: KeyValuePersistible {
    /// The default value for the key.
    /// 
    /// This value is used when the key has not been set.
    public let defaultValue: Value

    /// The unique identifier for the key.
    ///
    /// This value must be unique across all keys in a given ``PersistentKeyValueStore``.
    public let id: String
    
    // MARK: Public Initialization
    
    /// Creates a new key with the given identifier and default value.
    ///
    /// - Parameter id: The unique identifier for the key.
    /// - Parameter defaultValue: The default value for the key.
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
    // MARK: Interfacing with User Defaults

    /// Gets the value of the key from the given `UserDefaults`.
    ///
    /// The default value is returned if the key has not been set.
    ///
    /// - Parameter userDefaults: The `UserDefaults` to get the value from.
    /// - Returns: The value of the key in the given `UserDefaults`, or the default value if the key has not been set.
    @inlinable
    public func get(from userDefaults: UserDefaults) -> Value {
        .deserialize(for: self, from: Value.get(self, from: userDefaults))
    }
    
    /// Removes the value of the key from the given `UserDefaults`.
    ///
    /// - Parameter userDefaults: The `UserDefaults` to remove the value from.
    @inlinable
    public func remove(from userDefaults: UserDefaults) {
        userDefaults.removeObject(forKey: id)
    }
    
    /// Sets the value of the key to the given value in the given `UserDefaults`.
    ///
    /// - Parameter newValue: The new value for the key.
    /// - Parameter userDefaults: The `UserDefaults` to set the value in.
    @inlinable
    public func set(to newValue: Value, in userDefaults: UserDefaults) {
        newValue.store(as: id, in: userDefaults)
    }
    
    #if !os(watchOS)

    // MARK: Interfacing with Ubiquitous Key-Value Store
    
    /// Gets the value of the key from the given `NSUbiquitousKeyValueStore`.
    ///
    /// The default value is returned if the key has not been set.
    ///
    /// - Parameter ubiquitousStore: The `NSUbiquitousKeyValueStore` to get the value from.
    /// - Returns: The value of the key in the given `NSUbiquitousKeyValueStore`, or the default value if the key has 
    ///   not been set.
    @inlinable
    public func get(from ubiquitousStore: NSUbiquitousKeyValueStore) -> Value {
        .deserialize(for: self, from: Value.get(self, from: ubiquitousStore))
    }
    
    /// Removes the value of the key from the given `NSUbiquitousKeyValueStore`.
    ///
    /// - Parameter ubiquitousStore: The `NSUbiquitousKeyValueStore` to remove the value from.
    @inlinable
    public func remove(from ubiquitousStore: NSUbiquitousKeyValueStore) {
        ubiquitousStore.removeObject(forKey: id)
    }
    
    /// Sets the value of the key to the given value in the given `NSUbiquitousKeyValueStore`.
    ///
    /// - Parameter newValue: The new value for the key.
    /// - Parameter ubiquitousStore: The `NSUbiquitousKeyValueStore` to set the value in.
    @inlinable
    public func set(to newValue: Value, in ubiquitousStore: NSUbiquitousKeyValueStore) {
        newValue.store(as: id, in: ubiquitousStore)
    }
    
    #endif
}
