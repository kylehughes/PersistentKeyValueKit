//
//  Array<KeyValuePersistible>+KeyValuePersistible.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 4/13/24.
//

import Foundation

// MARK: - KeyValuePersistible Extension

extension Array: KeyValuePersistible where Element: KeyValuePersistible {
    // MARK: Public Static Interface

    /// The representation of an array in a ``PersistentKeyValueStore``.
    ///
    /// Writes are all or nothing: if any element fails to encode, the store or container is left unchanged, so a
    /// failed write never partially overwrites a stored array. Elements that encode to `nil`, such as `nil` optionals,
    /// are omitted. An element representation defined outside this package reports a failure by leaving the array
    /// empty, so a write fails if that representation encodes every element of a nonempty array to `nil`. Reads are
    /// also all or nothing: if any element fails to decode, the read returns `nil` and a key falls back to its default
    /// value, because an element's position can carry meaning.
    @inlinable
    public static var persistentKeyValueRepresentation: some PersistentKeyValueRepresentation<Self> {
        PrimitivePersistentKeyValueRepresentation()
    }
}

// MARK: - BuiltInContainerPrimitive Extension

extension Array: BuiltInContainerPrimitive where Element: KeyValuePersistible {}

// MARK: - BuiltInPrimitive Extension

extension Array: BuiltInPrimitive where Element: KeyValuePersistible {}

// MARK: - PrimitiveKeyValuePersistible Extension

extension Array: PrimitiveKeyValuePersistible where Element: KeyValuePersistible {
    /// Decodes an array of elements from a stored `[Any]` array.
    ///
    /// Throws if the array cannot be decoded. This checked conversion is stricter than ordinary reads: a nested
    /// dictionary fails instead of omitting an entry that fails to decode or merging canonically equivalent keys.
    /// When every representation in the element's conversion chain is built in, each element finishes decoding with
    /// its own checked conversion, including a proxy representation's conversion of the decoded proxy, before the next
    /// is read, and the first error in input order is rethrown. A representation defined outside this package decodes
    /// the array with its ``PersistentKeyValueRepresentation/get(from:)`` exactly as it is implemented, so a custom
    /// array format round-trips, and throws ``PersistentKeyValueConversionError/invalidStorageValue`` when it returns
    /// `nil`. A built-in proxy representation over it converts the decoded proxies only after that read succeeds, so
    /// the read's error is thrown even when an earlier element's proxy conversion would fail.
    public static func decode(
        storageObject: Any,
        format: PersistentKeyValueStorageFormat
    ) throws -> [Element] {
        guard let objects = storageObject as? [Any] else {
            throw PersistentKeyValueConversionError.invalidStorageValue
        }

        return try Element.persistentKeyValueRepresentation.checkedValues(decoding: objects)
    }

    /// Encodes the elements into a `[Any]` array, omitting elements whose encoding returns `nil`.
    ///
    /// Throws if any element fails to encode. Built-in element representations encode each element with their own
    /// checked conversion (converting outer proxy layers before encoding the resulting proxies) and rethrow the
    /// thrown error. Other element representations encode the array with their
    /// ``PersistentKeyValueRepresentation/set(_:to:)`` exactly as it is implemented and throw
    /// ``PersistentKeyValueConversionError/encodingFailed`` when it leaves the array empty for nonempty values or
    /// writes an object that is not a property list that `UserDefaults` and `NSUbiquitousKeyValueStore` accept.
    public func encode(format: PersistentKeyValueStorageFormat) throws -> Any? {
        try Element.persistentKeyValueRepresentation.checkedPropertyListArray(encoding: self)
    }

    // MARK: Interfacing with Property List Array
    
    public static func get(from propertyListArray: [Any]) -> [Self]? {
        let representation = Element.persistentKeyValueRepresentation
        
        var originalArray: [Self] = []
        
        originalArray.reserveCapacity(propertyListArray.count)
        
        for primitiveElement in propertyListArray {
            guard
                let primitiveChildArray = primitiveElement as? [Any],
                let childArray = representation.get(from: primitiveChildArray)
            else {
                return nil
            }
            
            originalArray.append(childArray)
        }
        
        return originalArray
    }
    
    /// Replaces `propertyListArray` with the encoded child arrays.
    ///
    /// Leaves `propertyListArray` unchanged if any element of any child array fails to encode.
    public static func set(_ values: [Self], to propertyListArray: inout [Any]) {
        let representation = Element.persistentKeyValueRepresentation

        guard let childPropertyListArrays = representation.propertyListArrays(encoding: values) else {
            return
        }

        propertyListArray = childPropertyListArrays
    }

    // MARK: Interfacing with Property List Dictionary
    
    @inlinable
    public static func get(_ dictionaryKey: String, from propertyListDictionary: [String: Any]) -> Self? {
        guard let propertyListArray = propertyListDictionary[dictionaryKey] as? [Any] else {
            return nil
        }
        
        return Element.persistentKeyValueRepresentation.get(from: propertyListArray)
    }
    
    /// Sets the encoded array at `dictionaryKey`, leaving `propertyListDictionary` unchanged if any element fails to
    /// encode.
    @inlinable
    public static func set(_ dictionaryKey: String, to value: Self, in propertyListDictionary: inout [String: Any]) {
        guard let propertyListArray = Element.persistentKeyValueRepresentation.propertyListArray(encoding: value) else {
            return
        }

        propertyListDictionary[dictionaryKey] = propertyListArray
    }

    // MARK: Interfacing with User Defaults
    
    @inlinable
    public static func get(_ userDefaultsKey: String, from userDefaults: UserDefaults) -> Self? {
        guard let propertyListArray = userDefaults.array(forKey: userDefaultsKey) else {
            return nil
        }
        
        return Element.persistentKeyValueRepresentation.get(from: propertyListArray)
    }
    
    /// Writes the encoded array, leaving `userDefaults` unchanged if any element fails to encode.
    @inlinable
    public static func set(_ userDefaultsKey: String, to value: Self, in userDefaults: UserDefaults) {
        guard let propertyListArray = Element.persistentKeyValueRepresentation.propertyListArray(encoding: value) else {
            return
        }

        userDefaults.set(propertyListArray, forKey: userDefaultsKey)
    }

    // MARK: Interfacing with Ubiquitous Key-Value Store
    
    @available(watchOS 9.0, *)
    @inlinable
    public static func get(
        _ ubiquitousStoreKey: String,
        from ubiquitousStore: NSUbiquitousKeyValueStore
    ) -> Self? {
        guard let propertyListArray = ubiquitousStore.array(forKey: ubiquitousStoreKey) else {
            return nil
        }
        
        return Element.persistentKeyValueRepresentation.get(from: propertyListArray)
    }
    
    /// Writes the encoded array, leaving `ubiquitousStore` unchanged if any element fails to encode.
    @available(watchOS 9.0, *)
    @inlinable
    public static func set(
        _ ubiquitousStoreKey: String,
        to value: Self,
        in ubiquitousStore: NSUbiquitousKeyValueStore
    ) {
        guard let propertyListArray = Element.persistentKeyValueRepresentation.propertyListArray(encoding: value) else {
            return
        }

        ubiquitousStore.set(propertyListArray, forKey: ubiquitousStoreKey)
    }
}
