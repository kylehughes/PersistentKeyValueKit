//
//  PrimitiveKeyValuePersistible.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 4/13/24.
//

import Foundation

/// A protocol for a representation of a value in a ``PersistentKeyValueStore`` that is itself a persistible type and
/// defines explicitly how to interface with `UserDefaults` and `NSUbiquitousKeyValueStore`.
///
/// This protocol is intended for use with types that have explicit interfaces defined on `UserDefaults` and/or
/// `NSUbiquitousKeyValueStore`. All of those types already implement this protocol. Other types should prefer
/// proxy representations, like ``CodablePersistentKeyValueRepresentation`` or
/// ``ProxyPersistentKeyValueRepresentation``, which simplify the requirements and make the best performance decisions.
/// However, it is possible to use this type to create very specific or complex representations of a custom type within
/// a store, such as utilizing `[String: Any]` storage.
///
/// The built-in primitive types are:
/// - `Array<Element> where Element: KeyValuePersistible`
/// - `Bool`
/// - `Data`
/// - `Dictionary<String, Value> where Value: KeyValuePersistible`
/// - `Double`
/// - `Float`
/// - `Int`
/// - `Optional<Wrapped> where Wrapped: KeyValuePersistible`
/// - `String`
/// - `URL`
///
/// It is intended, but not required, that conforming types' representations are of type 
/// ``PrimitivePersistentKeyValueRepresentation``.
public protocol PrimitiveKeyValuePersistible: KeyValuePersistible {
    // MARK: Interfacing with Property List Array
    
    /// Get the values from the given property-list-compatible array, if they exist and if they can all be represented
    /// as `Self`.
    ///
    /// - Parameter propertyListArray: The array to get the values from.
    /// - Returns: The values from the array, or `nil` if any value cannot be represented as `Self`. Note that this
    ///   function will return `nil` if the array contains values of different types, as it enforces type homogeneity
    ///   across all elements.
    /// - Important: This function will return `nil` if the array contains values of different types, as it enforces
    ///   type homogeneity across all elements.
    static func get(from propertyListArray: [Any]) -> [Self]?
    
    /// Set the values in the given property-list-compatible array.
    ///
    /// - Parameter values: The values to set in the array. All values must be of the same type.
    /// - Parameter propertyListArray: The array to set the values in.
    static func set(_ values: [Self], to propertyListArray: inout [Any])
    
    // MARK: Interfacing with Property List Dictionary
    
    /// Get the value at the given key from the given property-list-compatible dictionary, if it exists and if it can
    /// be represented as `Self`.
    ///
    /// - Parameter dictionaryKey: The key to get the value from.
    /// - Parameter propertyListDictionary: The dictionary to get the value from at `dictionaryKey`.
    /// - Returns: The value at `dictionaryKey` in `propertyListDictionary`, or `nil` if it does not exist or cannot be
    ///   represented as `Self`.
    static func get(_ dictionaryKey: String, from propertyListDictionary: [String: Any]) -> Self?
    
    /// Set the value at the given key in the given property-list-compatible dictionary.
    ///
    /// - Parameter dictionaryKey: The key to set the value at.
    /// - Parameter propertyListDictionary: The dictionary to set the value in at `dictionaryKey`.
    static func set(_ dictionaryKey: String, to value: Self, in propertyListDictionary: inout [String: Any])
    
    // MARK: Interfacing with User Defaults
    
    /// Get the value at the given key from the given `UserDefaults`, if it exists and if it can be represented as
    /// `Self`.
    ///
    /// - Parameter userDefaultsKey: The key to get the value from.
    /// - Parameter userDefaults: The `UserDefaults` to get the value from at `userDefaultsKey`.
    /// - Returns: The value at `userDefaultsKey` in `userDefaults`, or `nil` if it does not exist or cannot be
    ///   represented as `Self`.
    static func get(_ userDefaultsKey: String, from userDefaults: UserDefaults) -> Self?
    
    /// Set the value at the given key in the given `UserDefaults`.
    ///
    /// - Parameter userDefaultsKey: The key to set the value at.
    /// - Parameter userDefaults: The `UserDefaults` to set the value in at `userDefaultsKey`.
    static func set(_ userDefaultsKey: String, to value: Self, in userDefaults: UserDefaults)
    
    // MARK: Interfacing with Ubiquitous Key-Value Store
    
    /// Get the value at the given key from the given `NSUbiquitousKeyValueStore`, if it exists and if it can be
    /// represented as `Self`.
    ///
    /// - Parameter ubiquitousStoreKey: The key to get the value from.
    /// - Parameter ubiquitousStore: The `NSUbiquitousKeyValueStore` to get the value from at
    ///   `ubiquitousStoreKey`.
    /// - Returns: The value at `ubiquitousStoreKey` in `ubiquitousStore`, or `nil` if it does not exist or cannot be
    ///   represented as `Self`.
    @available(watchOS 9.0, *)
    static func get(_ ubiquitousStoreKey: String, from ubiquitousStore: NSUbiquitousKeyValueStore) -> Self?
    
    /// Set the value at the given key in the given `NSUbiquitousKeyValueStore`.
    ///
    /// - Parameter ubiquitousStoreKey: The key to set the value at.
    /// - Parameter ubiquitousStore: The `NSUbiquitousKeyValueStore` to set the value in at
    ///   `ubiquitousStoreKey`.
    @available(watchOS 9.0, *)
    static func set(_ ubiquitousStoreKey: String, to value: Self, in ubiquitousStore: NSUbiquitousKeyValueStore)
}

// MARK: - Default Implementation

extension PrimitiveKeyValuePersistible {
    // MARK: Interfacing with Property List Array
    
    @inlinable
    public static func get(from propertyListArray: [Any]) -> [Self]? {
        propertyListArray as? [Self]
    }
    
    @inlinable
    public static func set(_ value: [Self], to propertyListArray: inout [Any]) {
        propertyListArray = value
    }
    
    // MARK: Interfacing with Property List Dictionary
    
    @inlinable
    public static func get(_ dictionaryKey: String, from propertyListDictionary: [String: Any]) -> Self? {
        propertyListDictionary[dictionaryKey] as? Self
    }
    
    @inlinable
    public static func set(_ dictionaryKey: String, to value: Self, in propertyListDictionary: inout [String: Any]) {
        propertyListDictionary[dictionaryKey] = value
    }
}
