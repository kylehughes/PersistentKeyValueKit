//
//  KeyValueStorableAsCodable.swift
//  KeyValueKit
//
//  Created by Kyle Hughes on 2/25/24.
//

import Foundation

/// A type that can be stored in a ``PersistentKeyValueStore`` using its `Codable` implementation..
public protocol KeyValueStorableAsCodable: Codable, KeyValueStorable
where
    Storage == String
{
    // NO-OP
}

// MARK: - KeyValueStorable Extension

extension KeyValueStorableAsCodable {
    // MARK: Interfacing with User Defaults

    /// Get the value, as `Storage`, at the given key from the given `UserDefaults`.
    ///
    /// - Parameter userDefaultsKey: The key to get the value from.
    /// - Parameter userDefaults: The `UserDefaults` to get the value from, as `Storage`, at `userDefaultsKey`.
    /// - Returns: The value, as `Storage`, at `userDefaultsKey` in `userDefaults`, if it exists.
    @inlinable
    public static func get(_ userDefaultsKey: String, from userDefaults: UserDefaults) -> Storage? {
        .get(userDefaultsKey, from: userDefaults)
    }
    
    #if !os(watchOS)
    
    // MARK: Interfacing with Ubiquitous Key-Value Store

    /// Get the value, as `Storage`, at the given key from the given `NSUbiquitousKeyValueStore`.
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
        .get(ubiquitousStoreKey, from: ubiquitousStore)
    }

    #endif
}
