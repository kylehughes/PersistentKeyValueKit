//
//  Float+KeyValueStorable.swift
//  KeyValueKit
//
//  Created by Kyle Hughes on 2/25/24.
//

import Foundation

// MARK: - KeyValuePersistable Extension

extension Float: KeyValuePersistable {
    // MARK: Public Typealiases
    
    public typealias Persistence = Self
    
    // MARK: Interfacing With User Defaults
    
    @inlinable
    public static func extract(_ userDefaultsKey: String, from userDefaults: UserDefaults) -> Persistence? {
        // We use the default implementation with `object(forKey)` so that we can differentiate a `nil` value from
        // a 0 value.
        userDefaults.object(forKey: userDefaultsKey) as? Persistence
    }
    
    @inlinable
    public func store(_ value: Persistence, as userDefaultsKey: String, in userDefaults: UserDefaults) {
        userDefaults.set(value, forKey: userDefaultsKey)
    }
    
    #if !os(watchOS)

    @inlinable
    public static func extract(
        _ ubiquitousStoreKey: String,
        from ubiquitousStore: NSUbiquitousKeyValueStore
    ) -> Persistence? {
        // We use the default implementation with `object(forKey)` so that we can differentiate a `nil` value from
        // a 0 value.
        ubiquitousStore.object(forKey: ubiquitousStoreKey) as? Persistence
    }
    
    @inlinable
    public func store(
        _ value: Persistence,
        as ubiquitousStoreKey: String,
        in ubiquitousStore: NSUbiquitousKeyValueStore
    ) {
        ubiquitousStore.set(value, forKey: ubiquitousStoreKey)
    }

    #endif
}

// MARK: - KeyValueSerializable Extension

extension Float: KeyValueSerializable, KeyValueSerializableAsSelf {
    // MARK: Public Typealiases
    
    public typealias Serialization = Self
}

// MARK: - KeyValueStorable Extension

extension Float: KeyValueStorable {}
