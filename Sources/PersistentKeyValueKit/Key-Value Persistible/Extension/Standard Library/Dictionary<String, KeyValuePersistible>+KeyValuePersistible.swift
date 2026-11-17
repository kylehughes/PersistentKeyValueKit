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
    
    @inlinable
    public static var persistentKeyValueRepresentation: some PersistentKeyValueRepresentation<Self> {
        PrimitivePersistentKeyValueRepresentation()
    }
}

// MARK: - PrimitiveKeyValuePersistible Extension

extension Dictionary: PrimitiveKeyValuePersistible
where
    Key == String,
    Value: KeyValuePersistible
{
    public static func decode(
        storageObject: Any,
        format: PersistentKeyValueStorageFormat
    ) throws -> [String: Value] {
        guard let objects = storageObject as? [String: Any] else {
            throw PersistentKeyValueConversionError.invalidStorageValue
        }
        var values: [String: Value] = [:]
        for (key, object) in objects {
            values[key] = try Value.persistentKeyValueRepresentation.decode(
                storageObject: object,
                format: .propertyList
            )
        }
        return values
    }

    public func encode(format: PersistentKeyValueStorageFormat) throws -> Any? {
        var objects: [String: Any] = [:]
        for (key, value) in self {
            if let object = try encodeStorageRepresentation(
                Value.persistentKeyValueRepresentation,
                value: value,
                format: .propertyList
            )
            {
                objects[key] = object
            }
        }
        return objects
    }

    // MARK: Interfacing with Property List Array
    
    public static func get(from propertyListArray: [Any]) -> [Self]? {
        let representation = Value.persistentKeyValueRepresentation
        
        var originalArray: [Self] = []
        
        originalArray.reserveCapacity(propertyListArray.count)
        
        for propertyListElement in propertyListArray {
            guard let propertyListDictionary = propertyListElement as? [String: Any] else {
                return nil
            }
            
            originalArray.append(transformToOriginalDictionary(propertyListDictionary, using: representation))
        }
        
        return originalArray
    }
    
    @inlinable
    public static func set(_ values: [Self], to propertyListArray: inout [Any]) {
        let representation = Value.persistentKeyValueRepresentation

        propertyListArray = values.map {
            transformToPropertyListDictionary($0, using: representation)
        }
    }
    
    // MARK: Interfacing with Property List Dictionary
    
    @inlinable
    public static func get(_ dictionaryKey: String, from propertyListDictionary: [String: Any]) -> Self? {
        guard let propertyListDictionary = propertyListDictionary[dictionaryKey] as? [String: Any] else {
            return nil
        }
        
        return transformToOriginalDictionary(propertyListDictionary)
    }
    
    @inlinable
    public static func set(_ dictionaryKey: String, to value: Self, in propertyListDictionary: inout [String: Any]) {
        propertyListDictionary[dictionaryKey] = transformToPropertyListDictionary(value)
    }
    
    // MARK: Interfacing with User Defaults
    
    @inlinable
    public static func get(_ userDefaultsKey: String, from userDefaults: UserDefaults) -> Self? {
        guard let propertyListDictionary = userDefaults.dictionary(forKey: userDefaultsKey) else {
            return nil
        }
        
        return transformToOriginalDictionary(propertyListDictionary)
    }
    
    @inlinable
    public static func set(_ userDefaultsKey: String, to value: Self, in userDefaults: UserDefaults) {
        userDefaults.set(transformToPropertyListDictionary(value), forKey: userDefaultsKey)
    }
    
    // MARK: Interfacing with Ubiquitous Key-Value Store
    
    @available(watchOS 9.0, *)
    @inlinable
    public static func get(_ ubiquitousStoreKey: String, from ubiquitousStore: NSUbiquitousKeyValueStore) -> Self? {
        guard let propertyListDictionary = ubiquitousStore.dictionary(forKey: ubiquitousStoreKey) else {
            return nil
        }
        
        return transformToOriginalDictionary(propertyListDictionary)
    }
    
    @available(watchOS 9.0, *)
    @inlinable
    public static func set(
        _ ubiquitousStoreKey: String,
        to value: Self,
        in ubiquitousStore: NSUbiquitousKeyValueStore
    ) {
        ubiquitousStore.set(transformToPropertyListDictionary(value), forKey: ubiquitousStoreKey)
    }
    
    // MARK: Internal Static Interface
    
    @usableFromInline
    internal static func transformToOriginalDictionary(
        _ propertyListDictionary: [String: Any],
        using representation: Value.PersistentKeyValueRepresentation = Value.persistentKeyValueRepresentation
    ) -> [String: Value] {
        var originalDictionary: [String: Value] = Dictionary(minimumCapacity: propertyListDictionary.count)
        
        for (key, _) in propertyListDictionary {
            originalDictionary[key] = representation.get(key, from: propertyListDictionary)
        }
        
        return originalDictionary
    }
    
    @usableFromInline
    internal static func transformToPropertyListDictionary(
        _ originalDictionary: Self,
        using representation: Value.PersistentKeyValueRepresentation = Value.persistentKeyValueRepresentation
    ) -> [String: Any] {
        var propertyListDictionary: [String: Any] = Dictionary(minimumCapacity: originalDictionary.count)
        
        for (key, value) in originalDictionary {
            representation.set(key, to: value, in: &propertyListDictionary)
        }
        
        return propertyListDictionary
    }
}
