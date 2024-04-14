//
//  PersitenceRepresentation.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 4/13/24.
//

import Foundation

public protocol PersistentKeyValueRepresentation<Value> {
    // MARK: Associated Types
    
    associatedtype Value
    
    // MARK: Interfacing with User Defaults
    
    /// Get the value, as `Storage`, at the given key from the given `UserDefaults`.
    ///
    /// - Parameter userDefaultsKey: The key to get the value from.
    /// - Parameter userDefaults: The `UserDefaults` to get the value from, as `Storage`, at `userDefaultsKey`.
    /// - Returns: The value, as `Storage`, at `userDefaultsKey` in `userDefaults`, if it exists.
    func get(_ userDefaultsKey: String, from userDefaults: UserDefaults) -> Value?
    
    /// Set the value, as `Storage`, at the given key in the given `UserDefaults`.
    ///
    /// - Parameter userDefaultsKey: The key to set the value at.
    /// - Parameter userDefaults: The `UserDefaults` to set the value in, as `Storage`, at `userDefaultsKey`.
    func set(_ userDefaultsKey: String, to value: Value, in userDefaults: UserDefaults)
    
    // MARK: Interfacing with Ubiquitous Key-Value Store
    
    /// Get the value, as `Storage`, at the given key from the given `NSUbiquitousKeyValueStore`.
    ///
    /// - Parameter ubiquitousStoreKey: The key to get the value from.
    /// - Parameter ubiquitousStore: The `NSUbiquitousKeyValueStore` to get the value from, as `Storage`, at
    ///   `ubiquitousStoreKey`.
    /// - Returns: The value, as `Storage`, at `ubiquitousStoreKey` in `ubiquitousStore`, if it exists.
    func get(_ ubiquitousStoreKey: String, from ubiquitousStore: NSUbiquitousKeyValueStore) -> Value?
    
    /// Set the value, as `Storage`, at the given key in the given `NSUbiquitousKeyValueStore`.
    ///
    /// - Parameter ubiquitousStoreKey: The key to set the value at.
    /// - Parameter ubiquitousStore: The `NSUbiquitousKeyValueStore` to set the value in, as `Storage`, at
    ///   `ubiquitousStoreKey`.
    func set(_ ubiquitousStoreKey: String, to value: Value, in ubiquitousStore: NSUbiquitousKeyValueStore)
}
