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
{}

// MARK: - KeyValueStorable Implementation

extension KeyValuePersistableAsProxy {
    // MARK: Interfacing With User Defaults
    
    @inlinable
    public static func extract(_ userDefaultsKey: String, from userDefaults: UserDefaults) -> Persistence? {
        .extract(userDefaultsKey, from: userDefaults)
    }
    
    @inlinable
    public func store(_ value: Persistence, as userDefaultsKey: String, in userDefaults: UserDefaults) {
        value.store(value, as: userDefaultsKey, in: userDefaults)
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
        _ value: Persistence,
        as ubiquitousStoreKey: String,
        in ubiquitousStore: NSUbiquitousKeyValueStore
    ) {
        value.store(value, as: ubiquitousStoreKey, in: ubiquitousStore)
    }

    #endif
}
