//
//  Array<String>+KeyValueStorable.swift
//  KeyValueKit
//
//  Created by Kyle Hughes on 2/25/24.
//

import Foundation

// MARK: - KeyValuePersistable Extension

extension Array<String>: KeyValuePersistable {
    // MARK: Public Typealiases
    
    public typealias Persistence = Self
    
    // MARK: Interfacing With User Defaults

    @inlinable
    public static func extract(_ userDefaultsKey: String, from userDefaults: UserDefaults) -> Persistence? {
        userDefaults.stringArray(forKey: userDefaultsKey)
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
        ubiquitousStore.array(forKey: ubiquitousStoreKey) as? Persistence
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

extension Array<String>: KeyValueSerializable, KeyValueSerializableAsSelf {
    // MARK: Public Typealiases
    
    public typealias Serialization = Self
}

// MARK: - KeyValueStorable Extension

extension Array<String>: KeyValueStorable {}
