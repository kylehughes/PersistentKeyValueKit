//
//  Array<String>+KeyValueStorable.swift
//  KeyValueKit
//
//  Created by Kyle Hughes on 2/26/24.
//

import Foundation

// MARK: - KeyValueStorable Extension

extension Array<String>: KeyValueStorable {
    // MARK: Public Typealiases
    
    /// The type that values of this type are stored as in a ``PersistentKeyValueStore``.
    public typealias Storage = Self
    
    // MARK: Interfacing With User Defaults

    /// Get the value, as `Storage`, at the given key from the given `UserDefaults`.
    ///
    /// - Parameter userDefaultsKey: The key to get the value from.
    /// - Parameter userDefaults: The `UserDefaults` to get the value from, as `Storage`, at `userDefaultsKey`.
    /// - Returns: The value, as `Storage`, at `userDefaultsKey` in `userDefaults`, if it exists.
    @inlinable
    public static func get(_ userDefaultsKey: String, from userDefaults: UserDefaults) -> Storage? {
        userDefaults.stringArray(forKey: userDefaultsKey)
    }
    
    /// Set the value, as `Storage`, at the given key in the given `UserDefaults`.
    ///
    /// - Parameter userDefaultsKey: The key to set the value at.
    /// - Parameter userDefaults: The `UserDefaults` to set the value in, as `Storage`, at `userDefaultsKey`.
    @inlinable
    public func set(as userDefaultsKey: String, in userDefaults: UserDefaults) {
        userDefaults.set(self, forKey: userDefaultsKey)
    }
    
    #if !os(watchOS)

    // MARK: Interfacing With Ubiquitous Key-Value Store

    /// Get the value, as `Storage`, at the given key from the given `NSUbiquitousKeyValueStore`.
    ///
    /// - Parameter ubiquitousStoreKey: The key to get the value from.
    /// - Parameter ubiquitousStore: The `NSUbiquitousKeyValueStore` to get the value from, as `Storage`, at
    ///   `ubiquitousStoreKey`.
    @inlinable
    public static func get(
        _ ubiquitousStoreKey: String,
        from ubiquitousStore: NSUbiquitousKeyValueStore
    ) -> Storage? {
        ubiquitousStore.array(forKey: ubiquitousStoreKey) as? Storage
    }
    
    /// Set the value, as `Storage`, at the given key in the given `NSUbiquitousKeyValueStore`.
    ///
    /// - Parameter ubiquitousStoreKey: The key to set the value at.
    /// - Parameter ubiquitousStore: The `NSUbiquitousKeyValueStore` to set the value in, as `Storage`, at
    ///   `ubiquitousStoreKey`.
    @inlinable
    public func set(
        as ubiquitousStoreKey: String,
        in ubiquitousStore: NSUbiquitousKeyValueStore
    ) {
        ubiquitousStore.set(self, forKey: ubiquitousStoreKey)
    }

    #endif
}
