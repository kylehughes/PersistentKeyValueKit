//
//  Dictionary<String, KeyValuePersistible>+KeyValuePersistible.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 10/7/24.
//

import Foundation

// MARK: - KeyValuePersistible Extension

extension Dictionary: KeyValuePersistible where Key == String, Value: KeyValuePersistible {
    // MARK: Public Static Interface

    /// The representation of a `String`-keyed dictionary in a ``PersistentKeyValueStore``.
    ///
    /// Writes are all or nothing: if any value fails to encode, the store or container is left unchanged, so a failed
    /// write never partially overwrites a stored dictionary. Values that encode to `nil`, such as `nil` optionals, are
    /// omitted. A value representation defined outside this package reports a failure by leaving the entry absent, so
    /// a value that it encodes to `nil` fails the write. Ordinary reads
    /// keep every entry that decodes and omit entries that fail to decode, because entries are independent. Checked
    /// conversion through ``decode(storageObject:format:)``, which migration uses, fails if any entry fails to decode
    /// (unless a custom value representation's container hook omits nested entries).
    ///
    /// Foundation keeps keys that are canonically equivalent but spelled differently, such as composed and decomposed
    /// "café", as separate entries, while a Swift dictionary holds at most one of them. An ordinary read of a stored
    /// dictionary with such keys keeps one of the entries; which one is unspecified. Checked conversion fails instead.
    @inlinable
    public static var persistentKeyValueRepresentation: some PersistentKeyValueRepresentation<Self> {
        PrimitivePersistentKeyValueRepresentation()
    }
}

// MARK: - BuiltInContainerPrimitive Extension

extension Dictionary: BuiltInContainerPrimitive where Key == String, Value: KeyValuePersistible {}

// MARK: - BuiltInPrimitive Extension

extension Dictionary: BuiltInPrimitive where Key == String, Value: KeyValuePersistible {}

// MARK: - PrimitiveKeyValuePersistible Extension

extension Dictionary: PrimitiveKeyValuePersistible
where
    Key == String,
    Value: KeyValuePersistible
{
    /// Decodes a dictionary from a stored `[String: Any]` dictionary.
    ///
    /// Throws if any entry fails to decode, or if the stored dictionary has keys that are canonically equivalent but
    /// spelled differently, which a Swift dictionary cannot hold separately. This checked conversion is stricter than
    /// ordinary reads, which omit entries that fail to decode, so a migration reports the failure instead of dropping
    /// data. Built-in value representations decode each entry with their own checked conversion and rethrow the first
    /// error. Other value representations decode each entry with their
    /// ``PersistentKeyValueRepresentation/get(_:from:)-teh7`` exactly as it is implemented and throw
    /// ``PersistentKeyValueConversionError/invalidStorageValue`` when it returns `nil`.
    public static func decode(
        storageObject: Any,
        format: PersistentKeyValueStorageFormat
    ) throws -> [String: Value] {
        guard let objects = storageObject as? [String: Any] else {
            throw PersistentKeyValueConversionError.invalidStorageValue
        }

        // Bridging to a Swift dictionary merges canonically equivalent keys that Foundation stores separately.
        if let nativeObjects = storageObject as? NSDictionary, nativeObjects.count != objects.count {
            throw PersistentKeyValueConversionError.invalidStorageValue
        }

        return try Value.persistentKeyValueRepresentation.checkedDictionary(decoding: objects)
    }

    /// Encodes the dictionary into a `[String: Any]` dictionary.
    ///
    /// Throws if any value fails to encode. Built-in value representations encode each value with their own checked
    /// conversion, omit values that encode to `nil`, and rethrow the first error. Other value representations encode
    /// each entry with their ``PersistentKeyValueRepresentation/set(_:to:in:)-91w4n`` exactly as it is implemented and
    /// throw ``PersistentKeyValueConversionError/encodingFailed`` when it leaves the entry absent.
    public func encode(format: PersistentKeyValueStorageFormat) throws -> Any? {
        try Value.persistentKeyValueRepresentation.checkedPropertyListDictionary(encoding: self)
    }

    // MARK: Interfacing with Property List Array

    /// Decodes every element of `propertyListArray` as a dictionary, returning `nil` if any element is not a
    /// dictionary.
    ///
    /// Entries of each dictionary that fail to decode are omitted, as in other dictionary reads.
    public static func get(from propertyListArray: [Any]) -> [Self]? {
        let representation = Value.persistentKeyValueRepresentation

        var originalArray: [Self] = []

        originalArray.reserveCapacity(propertyListArray.count)

        for propertyListElement in propertyListArray {
            guard let propertyListDictionary = propertyListElement as? [String: Any] else {
                return nil
            }

            originalArray.append(representation.dictionary(decoding: propertyListDictionary))
        }

        return originalArray
    }

    /// Replaces `propertyListArray` with the encoded dictionaries.
    ///
    /// Leaves `propertyListArray` unchanged if any entry of any dictionary fails to encode.
    @inlinable
    public static func set(_ values: [Self], to propertyListArray: inout [Any]) {
        guard
            let propertyListDictionaries = Value.persistentKeyValueRepresentation.propertyListDictionaries(
                encoding: values
            )
        else {
            return
        }

        propertyListArray = propertyListDictionaries
    }

    // MARK: Interfacing with Property List Dictionary

    /// Decodes the dictionary at `dictionaryKey`, returning `nil` if it is absent or is not a dictionary.
    ///
    /// Entries that fail to decode are omitted so the readable entries survive a read-modify-write.
    @inlinable
    public static func get(_ dictionaryKey: String, from propertyListDictionary: [String: Any]) -> Self? {
        guard let propertyListDictionary = propertyListDictionary[dictionaryKey] as? [String: Any] else {
            return nil
        }

        return Value.persistentKeyValueRepresentation.dictionary(decoding: propertyListDictionary)
    }

    /// Sets the encoded dictionary at `dictionaryKey`, omitting entries whose value encodes to `nil`.
    ///
    /// Leaves `propertyListDictionary` unchanged if any entry fails to encode, including an entry whose value a
    /// representation defined outside this package encodes to `nil`.
    @inlinable
    public static func set(_ dictionaryKey: String, to value: Self, in propertyListDictionary: inout [String: Any]) {
        guard let encodedDictionary = Value.persistentKeyValueRepresentation.propertyListDictionary(encoding: value)
        else {
            return
        }

        propertyListDictionary[dictionaryKey] = encodedDictionary
    }

    // MARK: Interfacing with User Defaults

    /// Decodes the dictionary at `userDefaultsKey`, returning `nil` if it is absent or is not a dictionary.
    ///
    /// Entries that fail to decode are omitted so the readable entries survive a read-modify-write.
    @inlinable
    public static func get(_ userDefaultsKey: String, from userDefaults: UserDefaults) -> Self? {
        guard let propertyListDictionary = userDefaults.dictionary(forKey: userDefaultsKey) else {
            return nil
        }

        return Value.persistentKeyValueRepresentation.dictionary(decoding: propertyListDictionary)
    }

    /// Writes the encoded dictionary, omitting entries whose value encodes to `nil`.
    ///
    /// Leaves `userDefaults` unchanged if any entry fails to encode, including an entry whose value a representation
    /// defined outside this package encodes to `nil`.
    @inlinable
    public static func set(_ userDefaultsKey: String, to value: Self, in userDefaults: UserDefaults) {
        let representation = Value.persistentKeyValueRepresentation

        guard let propertyListDictionary = representation.propertyListDictionary(encoding: value) else {
            return
        }

        userDefaults.set(propertyListDictionary, forKey: userDefaultsKey)
    }

    // MARK: Interfacing with Ubiquitous Key-Value Store

    /// Decodes the dictionary at `ubiquitousStoreKey`, returning `nil` if it is absent or is not a dictionary.
    ///
    /// Entries that fail to decode are omitted so the readable entries survive a read-modify-write.
    @available(watchOS 9.0, *)
    @inlinable
    public static func get(_ ubiquitousStoreKey: String, from ubiquitousStore: NSUbiquitousKeyValueStore) -> Self? {
        guard let propertyListDictionary = ubiquitousStore.dictionary(forKey: ubiquitousStoreKey) else {
            return nil
        }

        return Value.persistentKeyValueRepresentation.dictionary(decoding: propertyListDictionary)
    }

    /// Writes the encoded dictionary, omitting entries whose value encodes to `nil`.
    ///
    /// Leaves `ubiquitousStore` unchanged if any entry fails to encode, including an entry whose value a
    /// representation defined outside this package encodes to `nil`.
    @available(watchOS 9.0, *)
    @inlinable
    public static func set(
        _ ubiquitousStoreKey: String,
        to value: Self,
        in ubiquitousStore: NSUbiquitousKeyValueStore
    ) {
        let representation = Value.persistentKeyValueRepresentation

        guard let propertyListDictionary = representation.propertyListDictionary(encoding: value) else {
            return
        }

        ubiquitousStore.set(propertyListDictionary, forKey: ubiquitousStoreKey)
    }
}
