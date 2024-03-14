//
//  KeyValueStorable.swift
//  KeyValueKit
//
//  Created by Kyle Hughes on 2/25/24.
//

import Foundation

/// A type that can be stored in a ``PersistentKeyValueStore``.
///
/// The interface for this protocol is designed to allow special types to use their special storage functions on
/// `UserDefaults` and `NSUbiquitousKeyValueStore`. The special types are those that have specific storage functions on
/// `UserDefaults` and `NSUbiquitousKeyValueStore`. These are effectively the "raw" types for the framework, and we
/// try to make it easy for other types to be converted to and from these types so that we can always make use of the
/// most efficient storage functions.
///
/// For `UserDefaults`, these types are:
///
/// - `Any` (`get`)
/// - `Array<Any>` (`get`)
/// - `Array<String>` (`get`)
/// - `Bool` (`get`, `set`)
/// - `Data` (`get`)
/// - `Dictionary<String, Any>` (`get`)
/// - `Double` (`get`, `set`)
/// - `Float` (`get`, `set`)
/// - `String` (`get`)
/// - `URL` (`get`, `set`)
///
/// For `NSUbiquitousKeyValueStore`, these types are:
///
/// - `Any` (`get`, `set`)
/// - `Array<Any>` (`get`, `set`)
/// - `Bool` (`get`, `set`)
/// - `Data` (`get`, `set`)
/// - `Dictionary<String, Any>` (`get`, `set`)
/// - `Double` (`get`, `set`)
/// - `Int64` (`get`, `set`)
/// - `String` (`get`, `set`)
public protocol KeyValueStorable<Storage> {
    // MARK: Associated Types
    
    /// The type that values of this type are stored as in a ``PersistentKeyValueStore``.
    associatedtype Storage
    
    // MARK: Interfacing with User Defaults
    
    /// Extract the value, as `Storage`, at the given key from the given `UserDefaults`.
    ///
    /// - Parameter userDefaultsKey: The key to extract the value from.
    /// - Parameter userDefaults: The `UserDefaults` to extract the value from, as `Storage`, at `userDefaultsKey`.
    /// - Returns: The value, as `Storage`, at `userDefaultsKey` in `userDefaults`, if it exists.
    static func extract(_ userDefaultsKey: String, from userDefaults: UserDefaults) -> Storage?
    
    /// Store the value, as `Storage`, at the given key in the given `UserDefaults`.
    ///
    /// - Parameter userDefaultsKey: The key to store the value at.
    /// - Parameter userDefaults: The `UserDefaults` to store the value in, as `Storage`, at `userDefaultsKey`.
    func store(as userDefaultsKey: String, in userDefaults: UserDefaults)
    
    #if !os(watchOS)
    
    // MARK: Interfacing with Ubiquitous Key-Value Store
    
    /// Extract the value, as `Storage`, at the given key from the given `NSUbiquitousKeyValueStore`.
    ///
    /// - Parameter ubiquitousStoreKey: The key to extract the value from.
    /// - Parameter ubiquitousStore: The `NSUbiquitousKeyValueStore` to extract the value from, as `Storage`, at
    ///   `ubiquitousStoreKey`.
    /// - Returns: The value, as `Storage`, at `ubiquitousStoreKey` in `ubiquitousStore`, if it exists.
    static func extract(_ ubiquitousStoreKey: String, from ubiquitousStore: NSUbiquitousKeyValueStore) -> Storage?
    
    /// Store the value, as `Storage`, at the given key in the given `NSUbiquitousKeyValueStore`.
    ///
    /// - Parameter ubiquitousStoreKey: The key to store the value at.
    /// - Parameter ubiquitousStore: The `NSUbiquitousKeyValueStore` to store the value in, as `Storage`, at
    ///   `ubiquitousStoreKey`.
    func store(as ubiquitousStoreKey: String, in ubiquitousStore: NSUbiquitousKeyValueStore)
    
    #endif
}

// MARK: - Novel Implementation

extension KeyValueStorable {
    // MARK: Interfacing with User Defaults
    
    /// Store the value, as `Storage`, at the given key in the given `UserDefaults`.
    ///
    /// - Parameter key: The key to store the value at.
    /// - Parameter userDefaults: The `UserDefaults` to store the value in, as `Storage`, at `key`.
    @inlinable
    public static func extract(
        _ key: some PersistentKeyProtocol,
        from userDefaults: UserDefaults
    ) -> Storage? {
        extract(key.id, from: userDefaults)
    }
    
    #if !os(watchOS)
    
    // MARK: Interfacing with Ubiquitous Key-Value Store
    
    /// Store the value, as `Storage`, at the given key in the given `NSUbiquitousKeyValueStore`.
    ///
    /// - Parameter key: The key to store the value at.
    /// - Parameter ubiquitousStore: The `NSUbiquitousKeyValueStore` to store the value in, as `Storage`, at `key`.
    @inlinable
    public static func extract(
        _ key: some PersistentKeyProtocol,
        from ubiquitousStore: NSUbiquitousKeyValueStore
    ) -> Storage? {
        extract(key.id, from: ubiquitousStore)
    }
    
    #endif
}
