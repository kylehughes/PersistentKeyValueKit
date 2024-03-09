//
//  KeyValueStorableAsProxy.swift
//  KeyValueKit
//
//  Created by Kyle Hughes on 2/25/24.
//

import Foundation

public protocol KeyValueStorableAsProxy: KeyValueStorable
where
    Persistence: KeyValueStorable,
    Persistence == Persistence.Persistence
{
    // MARK: Instance Interface
    
    var persistenceValue: Persistence { get }
}

// MARK: - KeyValuePersistible Implementation

extension KeyValueStorableAsProxy {
    // MARK: Interfacing with User Defaults
    
    @inlinable
    public static func extract(_ userDefaultsKey: String, from userDefaults: UserDefaults) -> Persistence? {
        .extract(userDefaultsKey, from: userDefaults)
    }
    
    /// Store the value, as `Persistence`, at the given key in the given `UserDefaults`.
    ///
    /// - Parameter userDefaultsKey: The key to store the value at.
    /// - Parameter userDefaults: The `UserDefaults` to store the value in, as `Persistence`, at `userDefaultsKey`.
    @inlinable
    public func store(as userDefaultsKey: String, in userDefaults: UserDefaults) {
        persistenceValue.store(as: userDefaultsKey, in: userDefaults)
    }
    
    #if !os(watchOS)
    
    // MARK: Interfacing with Ubiquitous Key-Value Store

    @inlinable
    public static func extract(
        _ ubiquitousStoreKey: String,
        from ubiquitousStore: NSUbiquitousKeyValueStore
    ) -> Persistence? {
        .extract(ubiquitousStoreKey, from: ubiquitousStore)
    }
    
    @inlinable
    public func store(
        as ubiquitousStoreKey: String,
        in ubiquitousStore: NSUbiquitousKeyValueStore
    ) {
        persistenceValue.store(as: ubiquitousStoreKey, in: ubiquitousStore)
    }

    #endif
}

// MARK: - Default Implementation where Self Serializes to Proxy

extension KeyValueStorableAsProxy where Self: KeyValueSerializable, Persistence == Serialization {
    // MARK: Public Instance Interface
    
    @inlinable
    public var persistenceValue: Persistence {
        serialize()
    }
}
