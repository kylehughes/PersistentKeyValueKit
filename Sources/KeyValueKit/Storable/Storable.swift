//
//  Storable.swift
//  KeyValueKit
//
//  Created by Kyle Hughes on 3/29/22.
//

import Foundation

/// A type that can be a value in key-value storage implementations that conform to ``Storage``.
public protocol Storable {
    // MARK: Associated Types
    
    /// The underlying type that values of the ``Storable`` type are stored as. The ``Storable`` type is encoded to and
    /// decoded from this type.
    associatedtype StorableValue
    
    // MARK: Converting to and from Storable Value

    /// Creates a new instance by decoding from the given storable value.
    ///
    /// - Parameter storage: The closure that provides access to the value that should be decoded, if it exists.
    /// - Returns: A new instance that is representative of the given storable value, if it exists and if possible.
    static func decode(from storage: @autoclosure () -> StorableValue?) -> Self?
    
    /// Encodes this value so that it is suitable for storage.
    ///
    /// - Returns: The encoded version of this value that can be stored.
    func encodeForStorage() -> StorableValue
    
    // MARK: Interfacing with User Defaults
    
    static func extract(_ userDefaultsKey: String, from userDefaults: UserDefaults) -> StorableValue?
    
    func store(_ value: StorableValue, as userDefaultsKey: String, in userDefaults: UserDefaults)
    
    #if !os(watchOS)
    
    // MARK: Interfacing with Ubiquitous Key-Value Store
    
    static func extract(_ ubiquitousStoreKey: String, from ubiquitousStore: NSUbiquitousKeyValueStore) -> StorableValue?
    
    func store(_ value: StorableValue, as ubiquitousStoreKey: String, in ubiquitousStore: NSUbiquitousKeyValueStore)
    
    #endif
}

// MARK: - Default Implementation

extension Storable {
    // MARK: Interfacing with User Defaults
    
    @inlinable
    public static func extract(_ userDefaultsKey: String, from userDefaults: UserDefaults) -> StorableValue? {
        userDefaults.object(forKey: userDefaultsKey) as? StorableValue
    }
    
    @inlinable
    public func store(_ value: StorableValue, as userDefaultsKey: String, in userDefaults: UserDefaults) {
        userDefaults.set(value, forKey: userDefaultsKey)
    }
    
    #if !os(watchOS)
    
    // MARK: Interfacing with Ubiquitous Key-Value Store
    
    @inlinable
    public static func extract(
        _ ubiquitousStoreKey: String,
        from ubiquitousStore: NSUbiquitousKeyValueStore
    ) -> StorableValue? {
        ubiquitousStore.object(forKey: ubiquitousStoreKey) as? StorableValue
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

// MARK: - Default Implementation for Types Whose Storable Value is Self

extension Storable where StorableValue == Self {
    // MARK: Converting to and from Storable Value
    
    @inlinable
    public static func decode(from storage: @autoclosure () -> StorableValue?) -> Self? {
        storage()
    }
    
    @inlinable
    public func encodeForStorage() -> StorableValue {
        self
    }
}

// MARK: - Novel Implementation

extension Storable {
    // MARK: Converting to and from Storable Value
    
    @inlinable
    public static func decode<Key>(
        for key: Key,
        from storage: @autoclosure () -> StorableValue?
    ) -> Self where Key: StorageKeyProtocol, Key.Value == Self {
        decode(from: storage()) ?? key.defaultValue
    }
    
    // MARK: Interfacing with User Defaults
    
    @inlinable
    public static func extract<Key>(
        _ key: Key,
        from userDefaults: UserDefaults
    ) -> StorableValue? where Key: StorageKeyProtocol {
        extract(key.id, from: userDefaults)
    }
    
    #if !os(watchOS)
    
    // MARK: Interfacing with Ubiquitous Key-Value Store
    
    @inlinable
    public static func extract<Key>(
        _ key: Key,
        from ubiquitousStore: NSUbiquitousKeyValueStore
    ) -> StorableValue? where Key: StorageKeyProtocol {
        extract(key.id, from: ubiquitousStore)
    }
    
    #endif
}
