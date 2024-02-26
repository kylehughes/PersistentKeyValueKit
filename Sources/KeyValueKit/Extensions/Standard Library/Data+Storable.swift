//
//  Data+Storable.swift
//  KeyValueKit
//
//  Created by Kyle Hughes on 2/25/24.
//

import Foundation

// MARK: - Storable Extension

extension Data: Storable {
    // MARK: Public Typealiases
    
    public typealias StorableValue = Self

    // MARK: Interfacing With User Defaults

    @inlinable
    public static func extract(_ userDefaultsKey: String, from userDefaults: UserDefaults) -> StorableValue? {
        userDefaults.data(forKey: userDefaultsKey)
    }
    
    #if !os(watchOS)
    
    @inlinable
    public static func extract(
        _ ubiquitousStoreKey: String,
        from ubiquitousStore: NSUbiquitousKeyValueStore
    ) -> StorableValue? {
        ubiquitousStore.data(forKey: ubiquitousStoreKey)
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
