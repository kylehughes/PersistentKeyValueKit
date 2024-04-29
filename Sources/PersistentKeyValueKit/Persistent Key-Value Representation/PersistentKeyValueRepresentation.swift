//
//  PersitenceRepresentation.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 4/13/24.
//

import Foundation

/// A representation of a value in a ``PersistentKeyValueStore``.
public protocol PersistentKeyValueRepresentation<Value> {
    // MARK: Associated Types
    
    /// The type of value that is represented in a ``PersistentKeyValueStore``.
    associatedtype Value
    
    // MARK: Interfacing with User Defaults
    
    /// Get the value at the given key from the given `UserDefaults`, if it exists.
    ///
    /// - Parameter userDefaultsKey: The key to get the value from.
    /// - Parameter userDefaults: The `UserDefaults` to get the value from at `userDefaultsKey`.
    /// - Returns: The value at `userDefaultsKey` in `userDefaults`, if it exists.
    func get(_ userDefaultsKey: String, from userDefaults: UserDefaults) -> Value?
    
    /// Set the value at the given key in the given `UserDefaults`.
    ///
    /// - Parameter userDefaultsKey: The key to set the value at.
    /// - Parameter userDefaults: The `UserDefaults` to set the value in at `userDefaultsKey`.
    func set(_ userDefaultsKey: String, to value: Value, in userDefaults: UserDefaults)
    
    // MARK: Interfacing with Ubiquitous Key-Value Store
    
    /// Get the value at the given key from the given `NSUbiquitousKeyValueStore`, if it exists.
    ///
    /// - Parameter ubiquitousStoreKey: The key to get the value from.
    /// - Parameter ubiquitousStore: The `NSUbiquitousKeyValueStore` to get the value from at `ubiquitousStoreKey`.
    /// - Returns: The value at `ubiquitousStoreKey` in `ubiquitousStore`, if it exists.
    func get(_ ubiquitousStoreKey: String, from ubiquitousStore: NSUbiquitousKeyValueStore) -> Value?
    
    /// Set the value at the given key in the given `NSUbiquitousKeyValueStore`.
    ///
    /// - Parameter ubiquitousStoreKey: The key to set the value at.
    /// - Parameter ubiquitousStore: The `NSUbiquitousKeyValueStore` to set the value in at `ubiquitousStoreKey`.
    func set(_ ubiquitousStoreKey: String, to value: Value, in ubiquitousStore: NSUbiquitousKeyValueStore)
}
