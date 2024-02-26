//
//  KeyValuePersistableAsObject.swift
//  KeyValueKit
//
//  Created by Kyle Hughes on 2/25/24.
//

import Foundation

public protocol KeyValuePersistableAsObject: KeyValuePersistable {}

// MARK: - KeyValuePersistable Extension

extension KeyValuePersistableAsObject {
    // MARK: Interfacing with User Defaults
    
    @inlinable
    public static func extract(_ userDefaultsKey: String, from userDefaults: UserDefaults) -> Persistence? {
        userDefaults.object(forKey: userDefaultsKey) as? Persistence
    }
    
    @inlinable
    public func store(_ value: Persistence, as userDefaultsKey: String, in userDefaults: UserDefaults) {
        userDefaults.set(value, forKey: userDefaultsKey)
    }
    
    #if !os(watchOS)
    
    // MARK: Interfacing with Ubiquitous Key-Value Store
    
    @inlinable
    public static func extract(
        _ ubiquitousStoreKey: String,
        from ubiquitousStore: NSUbiquitousKeyValueStore
    ) -> Persistence? {
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
