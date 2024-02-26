//
//  KeyValuePersistable.swift
//  KeyValueKit
//
//  Created by Kyle Hughes on 2/25/24.
//

import Foundation

public protocol KeyValuePersistable {
    // MARK: Associated Types
    
    associatedtype Persistence
    
    // MARK: Interfacing with User Defaults
    
    static func extract(_ userDefaultsKey: String, from userDefaults: UserDefaults) -> Persistence?
    
    func store(_ value: Persistence, as userDefaultsKey: String, in userDefaults: UserDefaults)
    
    #if !os(watchOS)
    
    // MARK: Interfacing with Ubiquitous Key-Value Store
    
    static func extract(_ ubiquitousStoreKey: String, from ubiquitousStore: NSUbiquitousKeyValueStore) -> Persistence?
    
    func store(_ value: Persistence, as ubiquitousStoreKey: String, in ubiquitousStore: NSUbiquitousKeyValueStore)
    
    #endif
}

// MARK: - Novel Implementation

extension KeyValuePersistable {
    // MARK: Interfacing with User Defaults
    
    @inlinable
    public static func extract(_ key: some StorageKeyProtocol, from userDefaults: UserDefaults) -> Persistence? {
        extract(key.id, from: userDefaults)
    }
    
    #if !os(watchOS)
    
    // MARK: Interfacing with Ubiquitous Key-Value Store
    
    @inlinable
    public static func extract(
        _ key: some StorageKeyProtocol,
        from ubiquitousStore: NSUbiquitousKeyValueStore
    ) -> Persistence? {
        extract(key.id, from: ubiquitousStore)
    }
    
    #endif
}
