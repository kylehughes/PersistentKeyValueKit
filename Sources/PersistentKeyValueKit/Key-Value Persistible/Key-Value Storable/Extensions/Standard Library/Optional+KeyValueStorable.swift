//
//  Optional+KeyValueStorable.swift
//  KeyValueKit
//
//  Created by Kyle Hughes on 2/27/24.
//

import Foundation

// MARK: - KeyValueStorable Extension

extension Optional: KeyValueStorable where Wrapped: KeyValueStorable {
    // MARK: Public Typealiases
    
    /// The type that values of this type are stored as in a ``PersistentKeyValueStore``.
    public typealias Storage = Wrapped.Storage?
    
    // MARK: Interfacing with User Defaults

    /// Get the value, as `Storage`, at the given key from the given `UserDefaults`.
    ///
    /// - Parameter userDefaultsKey: The key to get the value from.
    /// - Parameter userDefaults: The `UserDefaults` to get the value from, as `Storage`, at `userDefaultsKey`.
    /// - Returns: The value, as `Storage`, at `userDefaultsKey` in `userDefaults`, if it exists.
    @inlinable
    public static func get(_ userDefaultsKey: String, from userDefaults: UserDefaults) -> Storage? {
        Wrapped.get(userDefaultsKey, from: userDefaults)
    }
    
    /// Set the value, as `Storage`, at the given key in the given `UserDefaults`.
    ///
    /// - Parameter userDefaultsKey: The key to set the value at.
    /// - Parameter userDefaults: The `UserDefaults` to set the value in, as `Storage`, at `userDefaultsKey`.
    @inlinable
    public func set(as userDefaultsKey: String, in userDefaults: UserDefaults) {
        switch self {
        case .none:
            userDefaults.removeObject(forKey: userDefaultsKey)
        case let .some(wrapped):
            wrapped.set(as: userDefaultsKey, in: userDefaults)
        }
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
        Wrapped.get(ubiquitousStoreKey, from: ubiquitousStore)
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
        switch self {
        case .none:
            ubiquitousStore.removeObject(forKey: ubiquitousStoreKey)
        case let .some(wrapped):
            wrapped.set(as: ubiquitousStoreKey, in: ubiquitousStore)
        }
    }

    #endif
}
