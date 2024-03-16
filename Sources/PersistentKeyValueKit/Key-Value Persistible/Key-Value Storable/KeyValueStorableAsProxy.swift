//
//  KeyValueStorableAsProxy.swift
//  KeyValueKit
//
//  Created by Kyle Hughes on 2/25/24.
//

import Foundation

/// A type that can be stored in a ``PersistentKeyValueStore`` as another type that is also ``KeyValueStorable``.
///
/// This is a helper protocol designed to provide common default implementations of ``KeyValueStorable``.
///
/// This protocol is useful for types that are ``KeyValueSerializable`` to a type that is also ``KeyValueStorable``. For
/// example, `Date` is serialized to `TimeInterval` (i.e. `Double`) and conforms to this protocol to leverage `Double`'s
/// ``KeyValueStorable`` implementation.
public protocol KeyValueStorableAsProxy: KeyValueStorable
where
    Storage: KeyValueStorable,
    Storage == Storage.Storage
{
    // MARK: Instance Interface
    
    /// The value to store in a ``PersistentKeyValueStore``.
    var storageValue: Storage { get }
}

// MARK: - KeyValuePersistible Implementation

extension KeyValueStorableAsProxy {
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
    
    /// Set the value, as `Storage`, at the given key in the given `UserDefaults`.
    ///
    /// - Parameter userDefaultsKey: The key to set the value at.
    /// - Parameter userDefaults: The `UserDefaults` to set the value in, as `Storage`, at `userDefaultsKey`.
    @inlinable
    public func set(as userDefaultsKey: String, in userDefaults: UserDefaults) {
        storageValue.set(as: userDefaultsKey, in: userDefaults)
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
        storageValue.set(as: ubiquitousStoreKey, in: ubiquitousStore)
    }

    #endif
}

// MARK: - Default Implementation where Self Serializes to Proxy

extension KeyValueStorableAsProxy where Self: KeyValueSerializable, Storage == Serialization {
    // MARK: Public Instance Interface
    
    /// The value to store in a ``PersistentKeyValueStore``.
    ///
    /// - Returns: The result of calling `serialize()`.
    @inlinable
    public var storageValue: Storage {
        serialize()
    }
}
