//
//  StorableAsProxy.swift
//  KeyValueKit
//
//  Created by Kyle Hughes on 2/25/24.
//

import Foundation

public protocol StorableAsProxy: Storable 
where
    StorableValue: Storable,
    StorableValue == StorableValue.StorableValue
{}

// MARK: - Storable Implementation

extension StorableAsProxy {
    // MARK: Interfacing With User Defaults
    
    @inlinable
    public static func extract(_ userDefaultsKey: String, from userDefaults: UserDefaults) -> StorableValue? {
        .extract(userDefaultsKey, from: userDefaults)
    }
    
    @inlinable
    public func store(_ value: StorableValue, as userDefaultsKey: String, in userDefaults: UserDefaults) {
        value.store(value, as: userDefaultsKey, in: userDefaults)
    }
    
    #if !os(watchOS)

    @inlinable
    public static func extract(
        _ ubiquitousStoreKey: String,
        from ubiquitousStore: NSUbiquitousKeyValueStore
    ) -> StorableValue? {
        .extract(ubiquitousStoreKey, from: ubiquitousStore)
    }
    
    @inlinable
    public func store(
        _ value: StorableValue,
        as ubiquitousStoreKey: String,
        in ubiquitousStore: NSUbiquitousKeyValueStore
    ) {
        value.store(value, as: ubiquitousStoreKey, in: ubiquitousStore)
    }

    #endif
}
