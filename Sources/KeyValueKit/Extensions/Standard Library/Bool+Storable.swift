//
//  Bool+Storable.swift
//  KeyValueKit
//
//  Created by Kyle Hughes on 2/25/24.
//

import Foundation

// MARK: - Storable Extension

extension Bool: Storable {
    // MARK: Public Typealiases
    
    public typealias StorableValue = Self

    // MARK: Interfacing With User Defaults
    
    @inlinable
    public static func extract(_ userDefaultsKey: String, from userDefaults: UserDefaults) -> StorableValue? {
        // We use the default implementation with `object(forKey)` so that we can differentiate a `nil` value from
        // a `false` value.
        userDefaults.object(forKey: userDefaultsKey) as? StorableValue
    }
    
    @inlinable
    public func store(_ value: StorableValue, as userDefaultsKey: String, in userDefaults: UserDefaults) {
        userDefaults.set(value, forKey: userDefaultsKey)
    }
    
    #if !os(watchOS)
    
    @inlinable
    public static func extract(
        _ ubiquitousStoreKey: String,
        from ubiquitousStore: NSUbiquitousKeyValueStore
    ) -> StorableValue? {
        // We use the default implementation with `object(forKey)` so that we can differentiate a `nil` value from
        // a `false` value.
        ubiquitousStore.object(forKey: ubiquitousStoreKey) as? StorableValue
    }
    
    @inlinable
    public func store(
        _ value: StorableValue,
        as ubiquitousStoreKey: String,
        in ubiquitousStore: NSUbiquitousKeyValueStore
    ) {
        ubiquitousStore.set(value, forKey: ubiquitousStoreKey)
    }
    
    #endif
}
