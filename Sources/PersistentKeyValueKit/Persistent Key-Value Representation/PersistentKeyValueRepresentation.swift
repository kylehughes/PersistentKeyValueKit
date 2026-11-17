//
//  PersistentKeyValueRepresentation.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 4/13/24.
//

import Foundation

/// A representation of a value in a ``PersistentKeyValueStore``.
///
/// Conforming types implement ``decode(storageObject:format:)`` and ``encode(_:format:)``. The store-specific `get`
/// and `set` methods have default implementations built on those conversions; implement them only to customize
/// access to a particular store.
public protocol PersistentKeyValueRepresentation<Value>: Sendable {
    // MARK: Associated Types
    
    /// The type of value that is represented in a ``PersistentKeyValueStore``.
    associatedtype Value

    /// Decodes a value from a stored object for the given storage format.
    ///
    /// Callers such as migration write validation may invoke conversion more than once for the same value; do not
    /// rely on a specific invocation count.
    ///
    /// - Parameter storageObject: The stored object read from the backing store or property-list container.
    /// - Parameter format: The storage format of `storageObject`.
    /// - Returns: The decoded value.
    func decode(storageObject: Any, format: PersistentKeyValueStorageFormat) throws -> Value

    /// Encodes a value into a stored object for the given storage format.
    ///
    /// Returning `nil` removes the key from a store (or omits the element from a property-list collection). Callers
    /// such as migration write validation may invoke conversion more than once for the same value; do not rely on a
    /// specific invocation count.
    ///
    /// - Parameter value: The value to encode.
    /// - Parameter format: The target storage format.
    /// - Returns: The encoded storage object, or `nil` to remove the key.
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

// MARK: - Default Implementation

/// Default store and container access built on ``PersistentKeyValueRepresentation/decode(storageObject:format:)`` and
/// ``PersistentKeyValueRepresentation/encode(_:format:)``.
///
/// Reads return `nil` when the stored object is absent or fails to decode. Writes remove the key when `encode`
/// returns `nil` and leave the store or container unchanged when `encode` throws or returns an object that is not a
/// property list. Property-list containers use ``PersistentKeyValueStorageFormat/propertyList``.
///
/// These defaults read the effective `UserDefaults` object without inspecting `UserDefaults.argumentDomain`, so they do
/// not coerce string launch arguments into typed values. Built-in representations implement these methods themselves
/// and keep that coercion.
extension PersistentKeyValueRepresentation {
    // MARK: Interfacing with Property List Array

    /// Decodes every element of `propertyListArray`, returning `nil` if any element fails to decode.
    public func get(from propertyListArray: [Any]) -> [Value]? {
        var values: [Value] = []

        values.reserveCapacity(propertyListArray.count)

        for object in propertyListArray {
            guard let value = decodedValue(from: object, format: .propertyList) else {
                return nil
            }

            values.append(value)
        }

        return values
    }

    /// Replaces `propertyListArray` with the encoded `values`, omitting elements whose `encode` returns `nil`.
    ///
    /// Leaves `propertyListArray` unchanged if encoding any element throws or returns an object that is not a property
    /// list.
    public func set(_ values: [Value], to propertyListArray: inout [Any]) {
        var objects: [Any] = []

        objects.reserveCapacity(values.count)

        for value in values {
            guard let object = encodedObject(for: value, format: .propertyList) else {
                return
            }

            if let object {
                objects.append(object)
            }
        }

        propertyListArray = objects
    }

    // MARK: Interfacing with Property List Dictionary

    /// Decodes the object at `dictionaryKey`, returning `nil` when it is absent or fails to decode.
    public func get(_ dictionaryKey: String, from propertyListDictionary: [String: Any]) -> Value? {
        propertyListDictionary[dictionaryKey].flatMap {
            decodedValue(from: $0, format: .propertyList)
        }
    }

    /// Writes the encoded object, removes `dictionaryKey` when `encode` returns `nil`, and leaves
    /// `propertyListDictionary` unchanged when `encode` throws or returns an object that is not a property list.
    public func set(_ dictionaryKey: String, to value: Value, in propertyListDictionary: inout [String: Any]) {
        guard let object = encodedObject(for: value, format: .propertyList) else {
            return
        }

        if let object {
            propertyListDictionary[dictionaryKey] = object
        } else {
            propertyListDictionary.removeValue(forKey: dictionaryKey)
        }
    }

    // MARK: Interfacing with User Defaults

    /// Decodes the object returned by `object(forKey:)`, returning `nil` when it is absent or fails to decode.
    ///
    /// This default does not inspect `UserDefaults.argumentDomain`, so it does not coerce string launch arguments into
    /// typed values. Built-in representations implement this method themselves and keep that coercion.
    public func get(_ userDefaultsKey: String, from userDefaults: UserDefaults) -> Value? {
        userDefaults.object(forKey: userDefaultsKey).flatMap {
            decodedValue(from: $0, format: .userDefaults)
        }
    }

    /// Writes the encoded object, removes the key when `encode` returns `nil`, and leaves `userDefaults` unchanged
    /// when `encode` throws.
    public func set(_ userDefaultsKey: String, to value: Value, in userDefaults: UserDefaults) {
        guard let object = encodedObject(for: value, format: .userDefaults) else {
            return
        }

        if let object {
            userDefaults.set(object, forKey: userDefaultsKey)
        } else {
            userDefaults.removeObject(forKey: userDefaultsKey)
        }
    }

    // MARK: Interfacing with Ubiquitous Key-Value Store

    /// Decodes the object returned by `object(forKey:)`, returning `nil` when it is absent or fails to decode.
    @available(watchOS 9.0, *)
    public func get(_ ubiquitousStoreKey: String, from ubiquitousStore: NSUbiquitousKeyValueStore) -> Value? {
        ubiquitousStore.object(forKey: ubiquitousStoreKey).flatMap {
            decodedValue(from: $0, format: .ubiquitousKeyValueStore)
        }
    }

    /// Writes the encoded object, removes the key when `encode` returns `nil`, and leaves `ubiquitousStore` unchanged
    /// when `encode` throws.
    @available(watchOS 9.0, *)
    public func set(_ ubiquitousStoreKey: String, to value: Value, in ubiquitousStore: NSUbiquitousKeyValueStore) {
        guard let object = encodedObject(for: value, format: .ubiquitousKeyValueStore) else {
            return
        }

        if let object {
            ubiquitousStore.set(object, forKey: ubiquitousStoreKey)
        } else {
            ubiquitousStore.removeObject(forKey: ubiquitousStoreKey)
        }
    }

    // MARK: Private Instance Interface

    private func decodedValue(from object: Any, format: PersistentKeyValueStorageFormat) -> Value? {
        try? decode(storageObject: object, format: format)
    }

    // `try?` would flatten `Any??`, conflating a failed encoding with a request to remove the key. The outer `nil`
    // means `encode` threw or produced an object that is not a property list; `.some(nil)` means remove.
    private func encodedObject(for value: Value, format: PersistentKeyValueStorageFormat) -> Any?? {
        do {
            return storableEncoding(try encode(value, format: format))
        } catch {
            return nil
        }
    }
}

/// The storage format used to encode or decode a persistent value.
public enum PersistentKeyValueStorageFormat: Sendable {
    /// A property-list container such as an array or dictionary.
    case propertyList

    /// An `NSUbiquitousKeyValueStore` domain.
    case ubiquitousKeyValueStore

    /// A `UserDefaults` persistent domain.
    case userDefaults
}

/// Errors thrown by built-in representations when converting between a Swift value and a stored object.
public enum PersistentKeyValueConversionError: Error, Equatable, Sendable {
    /// The stored object has an unexpected runtime type, is not a valid property list, or exceeds the target store's
    /// size limit.
    case invalidStorageValue

    /// The stored or proxied value could not be converted into the target Swift type.
    case invalidValue

    /// The Swift value could not be converted into its proxy or storage representation.
    case encodingFailed
}

/// Returns `object` wrapped for storage, or `nil` when it is not a property list that a store accepts.
///
/// Foundation stores raise an Objective-C exception for non-property-list objects, so the default write paths treat
/// such an object as a failed encoding.
internal func storableEncoding(_ object: Any?) -> Any?? {
    guard let object else {
        return .some(nil)
    }

    guard PropertyListSerialization.propertyList(object, isValidFor: .binary) else {
        return nil
    }

    return .some(object)
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
