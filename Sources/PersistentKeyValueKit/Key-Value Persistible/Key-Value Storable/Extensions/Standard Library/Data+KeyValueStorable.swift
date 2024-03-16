//
//  Data+KeyValueStorable.swift
//  KeyValueKit
//
//  Created by Kyle Hughes on 2/26/24.
//

import Foundation

// MARK: - KeyValueStorable Extension

extension Data: KeyValueStorable {
    // MARK: Public Typealiases
    
    /// The type that the conforming type is stored as in a ``PersistentKeyValueStore``.
    public typealias Storage = Self
    
    // MARK: Interfacing with User Defaults

    @inlinable
    public static func get(_ userDefaultsKey: String, from userDefaults: UserDefaults) -> Storage? {
        userDefaults.data(forKey: userDefaultsKey)
    }
    
    /// Set the value, as `Storage`, at the given key in the given `UserDefaults`.
    ///
    /// - Parameter userDefaultsKey: The key to set the value at.
    /// - Parameter userDefaults: The `UserDefaults` to set the value in, as `Storage`, at `userDefaultsKey`.
    @inlinable
    public func set(as userDefaultsKey: String, in userDefaults: UserDefaults) {
        userDefaults.set(self, forKey: userDefaultsKey)
    }
    
    #if !os(watchOS)
    
    // MARK: Interfacing with Ubiquitous Key-Value Store
    
    @inlinable
    public static func get(
        _ ubiquitousStoreKey: String,
        from ubiquitousStore: NSUbiquitousKeyValueStore
    ) -> Storage? {
        ubiquitousStore.data(forKey: ubiquitousStoreKey)
    }
    
    @inlinable
    public func set(
        as ubiquitousStoreKey: String,
        in ubiquitousStore: NSUbiquitousKeyValueStore
    ) {
        ubiquitousStore.set(self, forKey: ubiquitousStoreKey)
    }
    
    #endif
}
