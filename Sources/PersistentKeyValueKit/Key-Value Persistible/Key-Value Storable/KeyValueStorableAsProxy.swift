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
    
    @inlinable
    public static func extract(_ userDefaultsKey: String, from userDefaults: UserDefaults) -> Storage? {
        .extract(userDefaultsKey, from: userDefaults)
    }
    
    /// Store the value, as `Storage`, at the given key in the given `UserDefaults`.
    ///
    /// - Parameter userDefaultsKey: The key to store the value at.
    /// - Parameter userDefaults: The `UserDefaults` to store the value in, as `Storage`, at `userDefaultsKey`.
    @inlinable
    public func store(as userDefaultsKey: String, in userDefaults: UserDefaults) {
        storageValue.store(as: userDefaultsKey, in: userDefaults)
    }
    
    #if !os(watchOS)
    
    // MARK: Interfacing with Ubiquitous Key-Value Store

    @inlinable
    public static func extract(
        _ ubiquitousStoreKey: String,
        from ubiquitousStore: NSUbiquitousKeyValueStore
    ) -> Storage? {
        .extract(ubiquitousStoreKey, from: ubiquitousStore)
    }
    
    @inlinable
    public func store(
        as ubiquitousStoreKey: String,
        in ubiquitousStore: NSUbiquitousKeyValueStore
    ) {
        storageValue.store(as: ubiquitousStoreKey, in: ubiquitousStore)
    }

    #endif
}

// MARK: - Default Implementation where Self Serializes to Proxy

extension KeyValueStorableAsProxy where Self: KeyValueSerializable, Storage == Serialization {
    // MARK: Public Instance Interface
    
    @inlinable
    public var storageValue: Storage {
        serialize()
    }
}
