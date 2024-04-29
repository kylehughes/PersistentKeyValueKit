//
//  DirectPersistentKeyValueRepresentationProtocol.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 4/13/24.
//

import Foundation

/// A protocol for a representation of a value in a ``PersistentKeyValueStore`` that is itself a persistible type and
/// defines explicitly how to interface with `UserDefaults` and `NSUbiquitousKeyValueStore`.
///
/// This protocol is intended for use with types that have explicit interfaces defined on `UserDefaults` and/or
/// `NSUbiquitousKeyValueStore`. Other types should prefer proxy representations, like
/// ``CodablePersistentKeyValueRepresentation`` or ``ProxyPersistentKeyValueRepresentation``, which simplify the
/// requirements and make the best performance decisions.
///
/// For `UserDefaults`, these special types are:
/// - `Array<String>`
/// - `Bool`
/// - `Data`
/// - `Double`
/// - `Float`
/// - `Int`
/// - `String`
/// - `URL`
///
/// For `NSUbiquitousKeyValueStore`, these special types are:
/// - `Array<String>`
/// - `Bool`
/// - `Data`
/// - `Double`
/// - `Float`
/// - `Int`
/// - `String`
///
/// It is intended, but not required, that conforming types' representations are of type 
/// ``DirectPersistentKeyValueRepresentation``.
public protocol DirectPersistentKeyValueRepresentationProtocol: KeyValuePersistible {
    // MARK: Interfacing with User Defaults
    
    /// Get the value at the given key from the given `UserDefaults`, if it exists.
    ///
    /// - Parameter userDefaultsKey: The key to get the value from.
    /// - Parameter userDefaults: The `UserDefaults` to get the value from at `userDefaultsKey`.
    /// - Returns: The value at `userDefaultsKey` in `userDefaults`, if it exists.
    static func get(_ userDefaultsKey: String, from userDefaults: UserDefaults) -> Self?
    
    /// Set the value at the given key in the given `UserDefaults`.
    ///
    /// - Parameter userDefaultsKey: The key to set the value at.
    /// - Parameter userDefaults: The `UserDefaults` to set the value in at `userDefaultsKey`.
    static func set(_ userDefaultsKey: String, to value: Self, in userDefaults: UserDefaults)
    
    // MARK: Interfacing with Ubiquitous Key-Value Store
    
    /// Get the value at the given key from the given `NSUbiquitousKeyValueStore`, if it exists.
    ///
    /// - Parameter ubiquitousStoreKey: The key to get the value from.
    /// - Parameter ubiquitousStore: The `NSUbiquitousKeyValueStore` to get the value from at
    ///   `ubiquitousStoreKey`.
    /// - Returns: The value at `ubiquitousStoreKey` in `ubiquitousStore`, if it exists.
    static func get(_ ubiquitousStoreKey: String, from ubiquitousStore: NSUbiquitousKeyValueStore) -> Self?
    
    /// Set the value at the given key in the given `NSUbiquitousKeyValueStore`.
    ///
    /// - Parameter ubiquitousStoreKey: The key to set the value at.
    /// - Parameter ubiquitousStore: The `NSUbiquitousKeyValueStore` to set the value in at
    ///   `ubiquitousStoreKey`.
    static func set(_ ubiquitousStoreKey: String, to value: Self, in ubiquitousStore: NSUbiquitousKeyValueStore)
}
