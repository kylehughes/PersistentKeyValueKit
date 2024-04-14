//
//  Array<String>+KeyValuePersistible.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 4/13/24.
//

import Foundation

// MARK: - KeyValuePersistible Extension

extension Array<String>: NewKeyValuePersistible {
    public static let persistentKeyValueRepresentation = SelfPersistentKeyValueRepresentation<Self>()
}

// MARK: - StaticPersistentKeyValueRepresentation Extension

extension Array<String>: StaticPersistentKeyValueRepresentation {
    // MARK: Interfacing with User Defaults
    
    @inlinable
    public static func get(_ userDefaultsKey: String, from userDefaults: UserDefaults) -> Self? {
        userDefaults.stringArray(forKey: userDefaultsKey)
    }
    
    @inlinable
    public static func set(_ userDefaultsKey: String, to value: Self, in userDefaults: UserDefaults) {
        userDefaults.setValue(value, forKey: userDefaultsKey)
    }
    
    // MARK: Interfacing with Ubiquitous Key-Value Store
    
    @inlinable
    public static func get(
        _ ubiquitousStoreKey: String,
        from ubiquitousStore: NSUbiquitousKeyValueStore
    ) -> Self? {
        ubiquitousStore.array(forKey: ubiquitousStoreKey) as? Self
    }
    
    @inlinable
    public static func set(
        _ ubiquitousStoreKey: String,
        to value: Self,
        in ubiquitousStore: NSUbiquitousKeyValueStore
    ) {
        ubiquitousStore.setValue(value, forKey: ubiquitousStoreKey)
    }
}
