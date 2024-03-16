//
//  KeyValueStorableAsObject.swift
//  KeyValueKit
//
//  Created by Kyle Hughes on 2/25/24.
//

import Foundation

/// A type that can be stored in a ``PersistentKeyValueStore`` using its generic `object(forKey:)` implementation.
///
/// This protocol is useful for an initial implementation during development, but a more specific protocol, like 
/// ``KeyValueStorableAsProxy`` which can defer to a first-class type, is preferred for production use. This one relies 
/// on unsafe and unperformant casting to-and-from `Any`.
public protocol KeyValueStorableAsObject: KeyValueStorable {
    // NO-OP
}

// MARK: - KeyValueStorable Extension

extension KeyValueStorableAsObject {
    // MARK: Interfacing with User Defaults
    
    /// Extract the value, as `Storage`, at the given key from the given `UserDefaults`.
    ///
    /// - Parameter userDefaultsKey: The key to get the value from.
    /// - Parameter userDefaults: The `UserDefaults` to get the value from, as `Storage`, at `userDefaultsKey`.
    /// - Returns: The value, as `Storage`, at `userDefaultsKey` in `userDefaults`, if it exists.
    @inlinable
    public static func get(_ userDefaultsKey: String, from userDefaults: UserDefaults) -> Storage? {
        userDefaults.object(forKey: userDefaultsKey) as? Storage
    }
    
    /// Store the value, as `Storage`, at the given key in the given `UserDefaults`.
    ///
    /// - Parameter userDefaultsKey: The key to store the value at.
    /// - Parameter userDefaults: The `UserDefaults` to store the value in, as `Storage`, at `userDefaultsKey`.
    @inlinable
    public func store(as userDefaultsKey: String, in userDefaults: UserDefaults) {
        userDefaults.set(self, forKey: userDefaultsKey)
    }
    
    #if !os(watchOS)
    
    // MARK: Interfacing with Ubiquitous Key-Value Store
    
    /// Extract the value, as `Storage`, at the given key from the given `NSUbiquitousKeyValueStore`.
    ///
    /// - Parameter ubiquitousStoreKey: The key to get the value from.
    /// - Parameter ubiquitousStore: The `NSUbiquitousKeyValueStore` to get the value from, as `Storage`, at
    ///   `ubiquitousStoreKey`.
    /// - Returns: The value, as `Storage`, at `ubiquitousStoreKey` in `ubiquitousStore`, if it exists.
    @inlinable
    public static func get(
        _ ubiquitousStoreKey: String,
        from ubiquitousStore: NSUbiquitousKeyValueStore
    ) -> Storage? {
        ubiquitousStore.object(forKey: ubiquitousStoreKey) as? Storage
    }
    
    /// Store the value, as `Storage`, at the given key in the given `NSUbiquitousKeyValueStore`.
    ///
    /// - Parameter ubiquitousStoreKey: The key to store the value at.
    /// - Parameter ubiquitousStore: The `NSUbiquitousKeyValueStore` to store the value in, as `Storage`, at
    ///   `ubiquitousStoreKey`.
    @inlinable
    public func store(
        as ubiquitousStoreKey: String,
        in ubiquitousStore: NSUbiquitousKeyValueStore
    ) {
        ubiquitousStore.set(self, forKey: ubiquitousStoreKey)
    }
    
    #endif
}
