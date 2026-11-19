//
//  PrimitiveKeyValuePersistible.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 4/13/24.
//

import Foundation

/// A ``KeyValuePersistible`` type that converts directly to and from the storage objects used by `UserDefaults`,
/// `NSUbiquitousKeyValueStore`, and property-list containers.
///
/// The built-in primitive types are:
/// - `Array<Element> where Element: KeyValuePersistible`
/// - `Bool`
/// - `Data`
/// - `Dictionary<String, Value> where Value: KeyValuePersistible`
/// - `Double`
/// - `Float`
/// - `Int`
/// - `String`
/// - `URL`
///
/// Most custom types should conform to ``KeyValuePersistible`` using a proxy representation such as
/// ``RawRepresentablePersistentKeyValueRepresentation``, ``CodablePersistentKeyValueRepresentation``,
/// ``LosslessStringConvertiblePersistentKeyValueRepresentation``, or ``ProxyPersistentKeyValueRepresentation``.
/// Conform to `PrimitiveKeyValuePersistible` (paired with ``PrimitivePersistentKeyValueRepresentation``) when a type
/// needs direct access to property-list storage such as `[String: Any]`.
///
/// Conforming types implement ``decode(storageObject:format:)`` and ``encode(format:)``. The store- and
/// container-specific `get` and `set` methods have default implementations built on those conversions, using
/// ``PersistentKeyValueStorageFormat/propertyList`` for property-list arrays and dictionaries. Built-in primitive
/// types implement these methods themselves.
///
/// An object that ``encode(format:)`` returns or a `set` method writes is handed over to the caller: do not mutate it
/// afterward, including a mutable string or data buffer, a mutable dictionary key, or a container. As a defense, the
/// default `set` methods and the conversion of `Array` and `Dictionary` values copy the mutable containers and leaf
/// values that they accept, except dictionary keys. ``PrimitivePersistentKeyValueRepresentation`` forwards its
/// container methods to this type's, so it writes the objects that those methods write without copying them. Behavior
/// is unspecified if a conforming type mutates an object after handing it over.
///
/// Built-in `Bool`, numeric, and `URL` primitives also coerce the string that a launch argument supplies in
/// `UserDefaults.argumentDomain`: a `Bool` accepts `1`, `true`, or `yes` and `0`, `false`, or `no` in any case, a
/// numeric type parses the trimmed string, and a `URL` argument requires a scheme. Coercion applies only when the
/// visible value is that argument string for the literal key, so a managed preference that overrides the key, or a
/// launch argument for another Unicode spelling of the identifier, does not coerce. Optional and proxy representations
/// inherit it. A custom primitive's default `UserDefaults` read does not coerce launch arguments.
///
/// In a target whose default isolation is `MainActor`, a conforming type's conversion members must be usable from
/// nonisolated code. Declaring the type and its conformance extension `nonisolated` does this; declaring each
/// conversion member, and the members it calls, `nonisolated` also works.
public protocol PrimitiveKeyValuePersistible: KeyValuePersistible {
    /// Decodes a value from a stored object for the given storage format.
    ///
    /// - Parameter storageObject: The stored object read from the backing store or property-list container.
    /// - Parameter format: The storage format of `storageObject`.
    /// - Returns: The decoded value.
    static func decode(storageObject: Any, format: PersistentKeyValueStorageFormat) throws -> Self

    /// Encodes the value into a stored object for the given storage format.
    ///
    /// The default Foundation setters remove the entry when this method returns `nil`; a custom setter can do
    /// otherwise. Collections apply their own rules. The default container methods omit such a value from a
    /// property-list collection, so an array can omit an element and still succeed, but an omission that leaves a
    /// dictionary entry absent or a nonempty array empty fails the write; see ``set(_:to:in:)-1ccdn`` and
    /// ``set(_:to:)``. Do not mutate the returned object, or any object it contains, after returning it.
    ///
    /// - Parameter format: The target storage format.
    /// - Returns: The encoded storage object, or `nil` for no stored object.
    func encode(format: PersistentKeyValueStorageFormat) throws -> Any?

    // MARK: Interfacing with Property List Array
    
    /// Decodes the elements of `propertyListArray` as `Self`.
    ///
    /// Array reads decode a stored array with this method, so it must accept the arrays that ``set(_:to:)`` writes.
    /// Checked conversion, which migration and `UserDefaults.register(_:)` use, also calls this method for types
    /// defined outside this package, so an implementation that omits elements it cannot decode omits them from
    /// migrated values too, including when an optional, proxy, or nested collection representation reaches it.
    ///
    /// - Parameter propertyListArray: The array to decode values from.
    /// - Returns: The decoded values, or `nil` if any element cannot be decoded as `Self`.
    static func get(from propertyListArray: [Any]) -> [Self]?
    
    /// Writes the encoded representations of `values` into `propertyListArray`.
    ///
    /// Array writes, registration, and migration call this method with an empty `propertyListArray`, and an
    /// implementation may only assign the encoded array to it or append the encoded elements to it. The result is the
    /// stored form of `values` and need not contain each element's own encoding. Build the encoded array separately
    /// and assign or append it only after every value encodes, because the package stores a nonempty result as written.
    /// If any value fails to encode, leave `propertyListArray` empty. Callers rely on this to keep the stored collection when one of its elements
    /// cannot be encoded, so an empty result for nonempty `values` counts as a failure, even if every value encodes to
    /// `nil`. Do not mutate the objects written to `propertyListArray` after this method returns.
    ///
    /// - Parameter values: The values to encode into `propertyListArray`.
    /// - Parameter propertyListArray: The array to write the encoded values into.
    static func set(_ values: [Self], to propertyListArray: inout [Any])
    
    // MARK: Interfacing with Property List Dictionary
    
    /// Decodes the value at `dictionaryKey` in `propertyListDictionary`, if present and representable as `Self`.
    ///
    /// Dictionary reads decode a stored entry with this method, so it must accept the objects that
    /// ``set(_:to:in:)-1ccdn`` writes. Ordinary dictionary reads omit an entry for which this method returns `nil`.
    /// Checked conversion, which migration and `UserDefaults.register(_:)` use, also calls this method for types
    /// defined outside this package and fails instead, though it accepts a value from which this method has already
    /// omitted nested entries.
    ///
    /// - Parameter dictionaryKey: The key to look up.
    /// - Parameter propertyListDictionary: The dictionary to read from.
    /// - Returns: The decoded value at `dictionaryKey` in `propertyListDictionary`, or `nil` if it is absent or cannot
    ///   be decoded as `Self`.
    static func get(_ dictionaryKey: String, from propertyListDictionary: [String: Any]) -> Self?
    
    /// Sets the value at `dictionaryKey` in `propertyListDictionary`.
    ///
    /// Write only the entry for `dictionaryKey`; do not read, modify, add, or remove other entries. If `value` fails to
    /// encode, leave `propertyListDictionary` unchanged; if it encodes to `nil`, remove `dictionaryKey`. Dictionary
    /// writes, registration, and migration call this method for a `dictionaryKey` that `propertyListDictionary` does
    /// not yet contain, and rely on this to keep the stored dictionary when one of its values cannot be encoded, so an
    /// absent entry counts as a failure, even if the value encodes to `nil`. Do not mutate the object written to the
    /// entry after this method returns.
    ///
    /// - Parameter dictionaryKey: The key to update.
    /// - Parameter value: The value to encode.
    /// - Parameter propertyListDictionary: The dictionary to update at `dictionaryKey`.
    static func set(_ dictionaryKey: String, to value: Self, in propertyListDictionary: inout [String: Any])
    
    // MARK: Interfacing with User Defaults
    
    /// Decodes the value at `userDefaultsKey` in `userDefaults`, if present and representable as `Self`.
    ///
    /// - Parameter userDefaultsKey: The key to look up.
    /// - Parameter userDefaults: The `UserDefaults` instance to read from.
    /// - Returns: The decoded value at `userDefaultsKey` in `userDefaults`, or `nil` if it is absent or cannot be
    ///   decoded as `Self`.
    static func get(_ userDefaultsKey: String, from userDefaults: UserDefaults) -> Self?
    
    /// Sets the value at `userDefaultsKey` in `userDefaults`.
    ///
    /// Do not mutate the object written to `userDefaults` after this method returns.
    ///
    /// - Parameter userDefaultsKey: The key to update.
    /// - Parameter value: The value to encode.
    /// - Parameter userDefaults: The `UserDefaults` instance to update at `userDefaultsKey`.
    static func set(_ userDefaultsKey: String, to value: Self, in userDefaults: UserDefaults)
    
    // MARK: Interfacing with Ubiquitous Key-Value Store
    
    /// Decodes the value at `ubiquitousStoreKey` in `ubiquitousStore`, if present and representable as `Self`.
    ///
    /// - Parameter ubiquitousStoreKey: The key to look up.
    /// - Parameter ubiquitousStore: The `NSUbiquitousKeyValueStore` instance to read from.
    /// - Returns: The decoded value at `ubiquitousStoreKey` in `ubiquitousStore`, or `nil` if it is absent or cannot
    ///   be decoded as `Self`.
    @available(watchOS 9.0, *)
    static func get(_ ubiquitousStoreKey: String, from ubiquitousStore: NSUbiquitousKeyValueStore) -> Self?
    
    /// Sets the value at `ubiquitousStoreKey` in `ubiquitousStore`.
    ///
    /// Do not mutate the object written to `ubiquitousStore` after this method returns.
    ///
    /// - Parameter ubiquitousStoreKey: The key to update.
    /// - Parameter value: The value to encode.
    /// - Parameter ubiquitousStore: The `NSUbiquitousKeyValueStore` instance to update at `ubiquitousStoreKey`.
    @available(watchOS 9.0, *)
    static func set(_ ubiquitousStoreKey: String, to value: Self, in ubiquitousStore: NSUbiquitousKeyValueStore)
}

// MARK: - Default Implementation

extension PrimitiveKeyValuePersistible {
    // MARK: Interfacing with Property List Array

    /// Decodes every element of `propertyListArray` with ``decode(storageObject:format:)``, returning `nil` if any
    /// element fails to decode.
    public static func get(from propertyListArray: [Any]) -> [Self]? {
        var values: [Self] = []

        values.reserveCapacity(propertyListArray.count)

        for object in propertyListArray {
            guard let value = try? decode(storageObject: object, format: .propertyList) else {
                return nil
            }

            values.append(value)
        }

        return values
    }

    /// Replaces `propertyListArray` with the objects returned by ``encode(format:)``, omitting elements that encode
    /// to `nil`.
    ///
    /// Leaves `propertyListArray` unchanged if encoding any element throws or returns an object that is not a property
    /// list.
    public static func set(_ values: [Self], to propertyListArray: inout [Any]) {
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

    /// Decodes the object at `dictionaryKey` with ``decode(storageObject:format:)``, returning `nil` when it is absent
    /// or fails to decode.
    public static func get(_ dictionaryKey: String, from propertyListDictionary: [String: Any]) -> Self? {
        propertyListDictionary[dictionaryKey].flatMap {
            try? decode(storageObject: $0, format: .propertyList)
        }
    }

    /// Writes the object returned by ``encode(format:)``, removes `dictionaryKey` when it returns `nil`, and leaves
    /// `propertyListDictionary` unchanged when it throws or returns an object that is not a property list.
    public static func set(_ dictionaryKey: String, to value: Self, in propertyListDictionary: inout [String: Any]) {
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

    /// Decodes the object stored at `userDefaultsKey` with ``decode(storageObject:format:)``, returning `nil` when the
    /// key is absent or decoding fails.
    ///
    /// This default does not inspect `UserDefaults.argumentDomain`, so it does not coerce string launch arguments into
    /// typed values. Built-in primitive types implement this method themselves and keep that coercion.
    public static func get(_ userDefaultsKey: String, from userDefaults: UserDefaults) -> Self? {
        userDefaults.object(forKey: userDefaultsKey).flatMap {
            try? decode(storageObject: $0, format: .userDefaults)
        }
    }

    /// Writes the object returned by ``encode(format:)``, removes the key when it returns `nil`, and leaves
    /// `userDefaults` unchanged when it throws or returns an object that is not a property list.
    public static func set(_ userDefaultsKey: String, to value: Self, in userDefaults: UserDefaults) {
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

    /// Decodes the object stored at `ubiquitousStoreKey` with ``decode(storageObject:format:)``, returning `nil` when
    /// the key is absent or decoding fails.
    @available(watchOS 9.0, *)
    public static func get(_ ubiquitousStoreKey: String, from ubiquitousStore: NSUbiquitousKeyValueStore) -> Self? {
        ubiquitousStore.object(forKey: ubiquitousStoreKey).flatMap {
            try? decode(storageObject: $0, format: .ubiquitousKeyValueStore)
        }
    }

    /// Writes the object returned by ``encode(format:)``, removes the key when it returns `nil`, and leaves
    /// `ubiquitousStore` unchanged when it throws or returns an object that is not a property list.
    @available(watchOS 9.0, *)
    public static func set(
        _ ubiquitousStoreKey: String,
        to value: Self,
        in ubiquitousStore: NSUbiquitousKeyValueStore
    ) {
        guard let object = encodedObject(for: value, format: .ubiquitousKeyValueStore) else {
            return
        }

        if let object {
            ubiquitousStore.set(object, forKey: ubiquitousStoreKey)
        } else {
            ubiquitousStore.removeObject(forKey: ubiquitousStoreKey)
        }
    }

    // MARK: Private Static Interface

    // `try?` would flatten `Any??`, conflating a failed encoding with a request to remove the key. The outer `nil`
    // means `encode` threw or produced an object that is not a property list; `.some(nil)` means remove.
    private static func encodedObject(for value: Self, format: PersistentKeyValueStorageFormat) -> Any?? {
        do {
            return storableEncoding(try value.encode(format: format))
        } catch {
            return nil
        }
    }
}
