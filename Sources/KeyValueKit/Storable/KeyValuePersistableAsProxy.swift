//
//  KeyValuePersistableAsProxy.swift
//  KeyValueKit
//
//  Created by Kyle Hughes on 2/25/24.
//

import Foundation

public protocol KeyValuePersistableAsProxy: KeyValuePersistable
where
    Persistence: KeyValuePersistable,
    Persistence == Persistence.Persistence
{
    var persistenceValue: Persistence { get }
}

// MARK: - KeyValueStorable Implementation

extension KeyValuePersistableAsProxy {
    // MARK: Interfacing With User Defaults
    
    @inlinable
    public static func extract(_ userDefaultsKey: String, from userDefaults: UserDefaults) -> Persistence? {
        .extract(userDefaultsKey, from: userDefaults)
    }
    
    @inlinable
    public func store(as userDefaultsKey: String, in userDefaults: UserDefaults) {
        persistenceValue.store(as: userDefaultsKey, in: userDefaults)
    }
    
    #if !os(watchOS)

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

extension KeyValuePersistableAsProxy where Self: KeyValueSerializable, Persistence == Serialization {
    // MARK: Public Instance Interface
    
    @inlinable
    public var persistenceValue: Persistence {
        serialize()
    }
}
