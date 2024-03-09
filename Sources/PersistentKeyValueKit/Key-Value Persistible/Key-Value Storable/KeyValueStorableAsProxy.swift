//
//  KeyValueStorableAsProxy.swift
//  KeyValueKit
//
//  Created by Kyle Hughes on 2/25/24.
//

import Foundation

public protocol KeyValueStorableAsProxy: KeyValueStorable
where
    Storage: KeyValueStorable,
    Storage == Storage.Storage
{
    // MARK: Instance Interface
    
    var StorageValue: Storage { get }
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
        StorageValue.store(as: userDefaultsKey, in: userDefaults)
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
        StorageValue.store(as: ubiquitousStoreKey, in: ubiquitousStore)
    }

    #endif
}

// MARK: - Default Implementation where Self Serializes to Proxy

extension KeyValueStorableAsProxy where Self: KeyValueSerializable, Storage == Serialization {
    // MARK: Public Instance Interface
    
    @inlinable
    public var StorageValue: Storage {
        serialize()
    }
}
