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

    /// Extract the value, as `Storage`, at the given key from the given `UserDefaults`.
    ///
    /// - Parameter userDefaultsKey: The key to extract the value from.
    /// - Parameter userDefaults: The `UserDefaults` to extract the value from, as `Storage`, at `userDefaultsKey`.
    /// - Returns: The value, as `Storage`, at `userDefaultsKey` in `userDefaults`, if it exists.
    @inlinable
    public static func extract(_ userDefaultsKey: String, from userDefaults: UserDefaults) -> Storage? {
        .extract(userDefaultsKey, from: userDefaults)
    }
    
    #if !os(watchOS)
    
    // MARK: Interfacing with Ubiquitous Key-Value Store

    /// Extract the value, as `Storage`, at the given key from the given `NSUbiquitousKeyValueStore`.
    ///
    /// - Parameter ubiquitousStoreKey: The key to extract the value from.
    /// - Parameter ubiquitousStore: The `NSUbiquitousKeyValueStore` to extract the value from, as `Storage`, at
    ///   `ubiquitousStoreKey`.
    /// - Returns: The value, as `Storage`, at `ubiquitousStoreKey` in `ubiquitousStore`, if it exists.
    @inlinable
    public static func extract(
        _ ubiquitousStoreKey: String,
        from ubiquitousStore: NSUbiquitousKeyValueStore
    ) -> Storage? {
        .extract(ubiquitousStoreKey, from: ubiquitousStore)
    }

    #endif
}
