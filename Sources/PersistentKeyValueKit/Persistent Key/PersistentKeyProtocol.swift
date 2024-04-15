//
//  PersistentKeyProtocol.swift
//  KeyValueKit
//
//  Created by Kyle Hughes on 4/17/22.
//

import Foundation

/// A protocol for a key for a value in a ``PersistentKeyValueStore``.
///
/// This interface is designed around the two persistent key-value stores provided by Apple platforms: `UserDefaults`
/// and `NSUbiquitousKeyValueStore`. It is not intended to support a generic key-value store implementation.
public protocol PersistentKeyProtocol<Value>: Identifiable where ID == String {
    // MARK: Associated Types
    
    /// The type of the value for the key.
    associatedtype Value: NewKeyValuePersistible
    
    // MARK: Instance Interface
    
    /// The default value for the key.
    ///
    /// This value is used when the key has not been set.
    var defaultValue: Value { get }

    /// The unique identifier for the key.
    ///
    /// This value must be unique across all keys in a given ``PersistentKeyValueStore``.
    var id: ID { get }

    // MARK: Interfacing with User Defaults
    
    /// Gets the value of the key from the given `UserDefaults`.
    ///
    /// The default value is returned if the key has not been set.
    ///
    /// - Parameter userDefaults: The `UserDefaults` to get the value from.
    /// - Returns: The value of the key in the given `UserDefaults`, or the default value if the key has not been set.
    func get(from userDefaults: UserDefaults) -> Value

    /// Removes the value of the key from the given `UserDefaults`.
    ///
    /// - Parameter userDefaults: The `UserDefaults` to remove the value from.
    func remove(from userDefaults: UserDefaults)

    /// Sets the value of the key to the given value in the given `UserDefaults`.
    ///
    /// - Parameter newValue: The new value for the key.
    /// - Parameter userDefaults: The `UserDefaults` to set the value in.
    func set(to newValue: Value, in userDefaults: UserDefaults)
    
    #if !os(watchOS)
    // MARK: Interfacing with Ubiquitous Key-Value Store

    /// Gets the value of the key from the given `NSUbiquitousKeyValueStore`.
    ///
    /// The default value is returned if the key has not been set.
    ///
    /// - Parameter ubiquitousStore: The `NSUbiquitousKeyValueStore` to get the value from.
    /// - Returns: The value of the key in the given `NSUbiquitousKeyValueStore`, or the default value if the key has 
    ///   not been set.
    func get(from ubiquitousStore: NSUbiquitousKeyValueStore) -> Value

    /// Removes the value of the key from the given `NSUbiquitousKeyValueStore`.
    ///
    /// - Parameter ubiquitousStore: The `NSUbiquitousKeyValueStore` to remove the value from.
    func remove(from ubiquitousStore: NSUbiquitousKeyValueStore)

    /// Sets the value of the key to the given value in the given `NSUbiquitousKeyValueStore`.
    ///
    /// - Parameter newValue: The new value for the key.
    /// - Parameter ubiquitousStore: The `NSUbiquitousKeyValueStore` to set the value in.
    func set(to newValue: Value, in ubiquitousStore: NSUbiquitousKeyValueStore)
    #endif
}
