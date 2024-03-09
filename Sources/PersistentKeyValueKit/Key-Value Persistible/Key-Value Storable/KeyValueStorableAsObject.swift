//
//  KeyValueStorableAsObject.swift
//  KeyValueKit
//
//  Created by Kyle Hughes on 2/25/24.
//

import Foundation

public protocol KeyValueStorableAsObject: KeyValueStorable {
    // NO-OP
}

// MARK: - KeyValueStorable Extension

extension KeyValueStorableAsObject {
    // MARK: Interfacing with User Defaults
    
    @inlinable
    public static func extract(_ userDefaultsKey: String, from userDefaults: UserDefaults) -> Storage? {
        userDefaults.object(forKey: userDefaultsKey) as? Storage
    }
    
    /// Store the value, as `Storage`, at the given key in the given `UserDefaults`.
    ///
    /// - Parameter userDefaultsKey: The key to store the value at.
    /// - Parameter userDefaults: The `UserDefaults` to store the value in, as `Storage`, at `userDefaultsKey`.
    @inlinable
    public func store(as userDefaultsKey: String, in userDefaults: UserDefaults) {
        userDefaults.set(self, forKey: userDefaultsKey)
    }
    
    #if !os(watchOS)
    
    // MARK: Interfacing with Ubiquitous Key-Value Store
    
    @inlinable
    public static func extract(
        _ ubiquitousStoreKey: String,
        from ubiquitousStore: NSUbiquitousKeyValueStore
    ) -> Storage? {
        ubiquitousStore.object(forKey: ubiquitousStoreKey) as? Storage
    }
    
    @inlinable
    public func store(
        as ubiquitousStoreKey: String,
        in ubiquitousStore: NSUbiquitousKeyValueStore
    ) {
        ubiquitousStore.set(self, forKey: ubiquitousStoreKey)
    }
    
    #endif
}
