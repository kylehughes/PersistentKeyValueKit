//
//  KeyValueStorable.swift
//  KeyValueKit
//
//  Created by Kyle Hughes on 2/25/24.
//

import Foundation

public protocol KeyValueStorable<Storage> {
    // MARK: Associated Types
    
    /// The type that the conforming type is stored as in a ``PersistentKeyValueStore``.
    associatedtype Storage
    
    // MARK: Interfacing with User Defaults
    
    static func extract(_ userDefaultsKey: String, from userDefaults: UserDefaults) -> Storage?
    
    /// Store the value, as `Storage`, at the given key in the given `UserDefaults`.
    ///
    /// - Parameter userDefaultsKey: The key to store the value at.
    /// - Parameter userDefaults: The `UserDefaults` to store the value in, as `Storage`, at `userDefaultsKey`.
    func store(as userDefaultsKey: String, in userDefaults: UserDefaults)
    
    #if !os(watchOS)
    
    // MARK: Interfacing with Ubiquitous Key-Value Store
    
    static func extract(_ ubiquitousStoreKey: String, from ubiquitousStore: NSUbiquitousKeyValueStore) -> Storage?
    
    func store(as ubiquitousStoreKey: String, in ubiquitousStore: NSUbiquitousKeyValueStore)
    
    #endif
}

// MARK: - Novel Implementation

extension KeyValueStorable {
    // MARK: Interfacing with User Defaults
    
    @inlinable
    public static func extract(
        _ key: some PersistentKeyProtocol,
        from userDefaults: UserDefaults
    ) -> Storage? {
        extract(key.id, from: userDefaults)
    }
    
    #if !os(watchOS)
    
    // MARK: Interfacing with Ubiquitous Key-Value Store
    
    @inlinable
    public static func extract(
        _ key: some PersistentKeyProtocol,
        from ubiquitousStore: NSUbiquitousKeyValueStore
    ) -> Storage? {
        extract(key.id, from: ubiquitousStore)
    }
    
    #endif
}
