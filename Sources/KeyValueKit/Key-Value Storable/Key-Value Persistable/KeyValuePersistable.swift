//
//  KeyValuePersistable.swift
//  KeyValueKit
//
//  Created by Kyle Hughes on 2/25/24.
//

import Foundation

public protocol KeyValuePersistable {
    // MARK: Associated Types
    
    /// The type that the conforming type is persisted as in a ``KeyValueStore``.
    associatedtype Persistence
    
    // MARK: Interfacing with User Defaults
    
    static func extract(_ userDefaultsKey: String, from userDefaults: UserDefaults) -> Persistence?
    
    /// Store the value, as `Persistence`, at the given key in the given `UserDefaults`.
    ///
    /// - Parameter userDefaultsKey: The key to store the value at.
    /// - Parameter userDefaults: The `UserDefaults` to store the value in, as `Persistence`, at `userDefaultsKey`.
    func store(as userDefaultsKey: String, in userDefaults: UserDefaults)
    
    #if !os(watchOS)
    
    // MARK: Interfacing with Ubiquitous Key-Value Store
    
    static func extract(_ ubiquitousStoreKey: String, from ubiquitousStore: NSUbiquitousKeyValueStore) -> Persistence?
    
    func store(as ubiquitousStoreKey: String, in ubiquitousStore: NSUbiquitousKeyValueStore)
    
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
