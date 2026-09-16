//
//  PersistentKeyValueRepresentation.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 4/13/24.
//

import Foundation

/// A representation of a value in a ``PersistentKeyValueStore``.
public protocol PersistentKeyValueRepresentation<Value>: Sendable {
    // MARK: Associated Types
    
    /// The type of value that is represented in a ``PersistentKeyValueStore``.
    associatedtype Value

    /// Decodes a stored object using the native format of a store.
    ///
    /// Clients may repeat conversion to validate a write. There is no guaranteed invocation count.
    func decode(storageObject: Any, format: PersistentKeyValueStorageFormat) throws -> Value

    /// Encodes a value using the native format of a store. A `nil` result removes the key.
    ///
    /// Clients may repeat conversion to validate a write. There is no guaranteed invocation count.
    func encode(_ value: Value, format: PersistentKeyValueStorageFormat) throws -> Any?
    
    // MARK: Interfacing with Property List Array
    
    /// Get the values from the given property-list-compatible array, if they exist and if they can all be represented
    /// as ``Value``.
    ///
    /// - Parameter propertyListArray: The array to get the values from.
    /// - Returns: The values from the array, or `nil` if any value cannot be represented as ``Value``. Note that this
    ///   function will return `nil` if the array contains values of different types, as it enforces type homogeneity
    ///   across all elements.
    /// - Important: This function will return `nil` if the array contains values of different types, as it enforces
    ///   type homogeneity across all elements.
    func get(from propertyListArray: [Any]) -> [Value]?

    /// Set the values in the given property-list-compatible array.
    ///
    /// - Parameter values: The values to set in the array. All values must be of the same type.
    /// - Parameter propertyListArray: The array to set the values in.
    func set(_ values: [Value], to propertyListArray: inout [Any])
    
    // MARK: Interfacing with Property List Dictionary

    /// Get the value at the given key from the given property-list-compatible dictionary, if it exists and if it can
    /// be represented as ``Value``.
    ///
    /// - Parameter dictionaryKey: The key to get the value from.
    /// - Parameter propertyListDictionary: The dictionary to get the value from at `dictionaryKey`.
    /// - Returns: The value at `dictionaryKey` in `dictionary`, or `nil` if it does not exist or cannot be represented
    ///   as ``Value``.
    func get(_ dictionaryKey: String, from propertyListDictionary: [String: Any]) -> Value?

    /// Set the value at the given key in the given property-list-compatible dictionary.
    ///
    /// - Parameter dictionaryKey: The key to set the value at.
    /// - Parameter value: The value to set the key to.
    /// - Parameter propertyListDictionary: The dictionary to set the value in at `dictionaryKey`.
    func set(_ dictionaryKey: String, to value: Value, in propertyListDictionary: inout [String: Any])
    
    // MARK: Interfacing with User Defaults
    
    /// Get the value at the given key from the given `UserDefaults`, if it exists and if it can be represented as
    /// ``Value``.
    ///
    /// - Parameter userDefaultsKey: The key to get the value from.
    /// - Parameter userDefaults: The `UserDefaults` to get the value from at `userDefaultsKey`.
    /// - Returns: The value at `userDefaultsKey` in `userDefaults`, or `nil` if it does not exist or cannot be
    ///   represented as ``Value``.
    func get(_ userDefaultsKey: String, from userDefaults: UserDefaults) -> Value?
    
    /// Set the value at the given key in the given `UserDefaults`.
    ///
    /// - Parameter userDefaultsKey: The key to set the value at.
    /// - Parameter value: The value to set the key to.
    /// - Parameter userDefaults: The `UserDefaults` to set the value in at `userDefaultsKey`.
    func set(_ userDefaultsKey: String, to value: Value, in userDefaults: UserDefaults)
    
    // MARK: Interfacing with Ubiquitous Key-Value Store
    
    /// Get the value at the given key from the given `NSUbiquitousKeyValueStore`, if it exists and if it can be
    /// represented as ``Value``.
    ///
    /// - Parameter ubiquitousStoreKey: The key to get the value from.
    /// - Parameter ubiquitousStore: The `NSUbiquitousKeyValueStore` to get the value from at `ubiquitousStoreKey`.
    /// - Returns: The value at `ubiquitousStoreKey` in `ubiquitousStore`, or `nil` if it does not exist or cannot be
    ///   represented as ``Value``.
    @available(watchOS 9.0, *)
    func get(_ ubiquitousStoreKey: String, from ubiquitousStore: NSUbiquitousKeyValueStore) -> Value?
    
    /// Set the value at the given key in the given `NSUbiquitousKeyValueStore`.
    ///
    /// - Parameter ubiquitousStoreKey: The key to set the value at.
    /// - Parameter value: The value to set the key to.
    /// - Parameter ubiquitousStore: The `NSUbiquitousKeyValueStore` to set the value in at `ubiquitousStoreKey`.
    @available(watchOS 9.0, *)
    func set(_ ubiquitousStoreKey: String, to value: Value, in ubiquitousStore: NSUbiquitousKeyValueStore)
}

/// The native storage format used to represent a persistent value.
public enum PersistentKeyValueStorageFormat: Sendable {
    case propertyList
    case ubiquitousKeyValueStore
    case userDefaults
}

/// A failure encountered while converting a value to or from store-native data.
public enum PersistentKeyValueConversionError: Error, Equatable, Sendable {
    case invalidStorageValue
    case invalidValue
    case encodingFailed
}

internal func checkedStorageValue<Value>(from object: Any, as type: Value.Type = Value.self) throws -> Value {
    guard let value = object as? Value else {
        throw PersistentKeyValueConversionError.invalidStorageValue
    }
    return value
}

internal func decodeStorageValue<Key: PersistentKeyProtocol>(
    for key: Key,
    object: Any,
    format: PersistentKeyValueStorageFormat
) throws -> Key.Value {
    try key.representation.decode(storageObject: object, format: format)
}

internal func encodeStorageRepresentation<Value, Representation: PersistentKeyValueRepresentation>(
    _ representation: Representation,
    value: Value,
    format: PersistentKeyValueStorageFormat
) throws -> Any?
where Representation.Value == Value {
    let object = try representation.encode(value, format: format)
    if let object {
        _ = try representation.decode(storageObject: object, format: format)
    }
    return object
}

internal func encodeStorageValue<Key: PersistentKeyProtocol>(
    _ value: Key.Value,
    for key: Key,
    format: PersistentKeyValueStorageFormat
) throws -> Any? {
    try encodeStorageRepresentation(key.representation, value: value, format: format)
}
