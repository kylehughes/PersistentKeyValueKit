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
    /// failed write never partially overwrites a stored array. Elements that encode to `nil` are omitted. Reads are
    /// also all or nothing: if any element fails to decode, the read returns `nil` and a key falls back to its default
    /// value, because an element's position can carry meaning.
    @inlinable
    public static var persistentKeyValueRepresentation: some PersistentKeyValueRepresentation<Self> {
        PrimitivePersistentKeyValueRepresentation()
    }
}

// MARK: - PrimitiveKeyValuePersistible Extension

extension Array: PrimitiveKeyValuePersistible where Element: KeyValuePersistible {
    /// Decodes an array of elements from a stored `[Any]` array using ``PersistentKeyValueStorageFormat/propertyList``.
    public static func decode(
        storageObject: Any,
        format: PersistentKeyValueStorageFormat
    ) throws -> [Element] {
        guard let objects = storageObject as? [Any] else {
            throw PersistentKeyValueConversionError.invalidStorageValue
        }
        return try objects.map {
            try Element.persistentKeyValueRepresentation.decode(
                storageObject: $0,
                format: .propertyList
            )
        }
    }

    /// Encodes the elements into a `[Any]` array using ``PersistentKeyValueStorageFormat/propertyList``, omitting
    /// elements whose encoding returns `nil`.
    public func encode(format: PersistentKeyValueStorageFormat) throws -> Any? {
        try compactMap { value in
            try encodeStorageRepresentation(
                Element.persistentKeyValueRepresentation,
                value: value,
                format: .propertyList
            )
        }
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

        var childPropertyListArrays: [Any] = []

        childPropertyListArrays.reserveCapacity(values.count)

        for value in values {
            guard let childPropertyListArray = representation.propertyListArray(encoding: value) else {
                return
            }

            childPropertyListArrays.append(childPropertyListArray)
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
