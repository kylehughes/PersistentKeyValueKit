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

    @inlinable
    public static var persistentKeyValueRepresentation: some PersistentKeyValueRepresentation<Self> {
        PrimitivePersistentKeyValueRepresentation()
    }
}

// MARK: - PrimitiveKeyValuePersistible Extension

extension Array: PrimitiveKeyValuePersistible where Element: KeyValuePersistible {
    // MARK: Interfacing with Property List Array
    
    public static func get(from propertyListArray: [Any]) -> [Self]? {
        let representation = Element.persistentKeyValueRepresentation
        
        var originalArray: [Self] = []
        
        originalArray.reserveCapacity(originalArray.capacity)
        
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
    
    public static func set(_ values: [Self], to propertyListArray: inout [Any]) {
        let representation = Element.persistentKeyValueRepresentation
        
        for value in values {
            var childPropertyListArray: [Any] = []
            
            childPropertyListArray.reserveCapacity(value.capacity)
            
            representation.set(value, to: &childPropertyListArray)
            
            propertyListArray.append(childPropertyListArray)
        }
    }
    
    // MARK: Interfacing with Property List Dictionary
    
    @inlinable
    public static func get(_ dictionaryKey: String, from propertyListDictionary: [String: Any]) -> Self? {
        guard let propertyListArray = propertyListDictionary[dictionaryKey] as? [Any] else {
            return nil
        }
        
        return Element.persistentKeyValueRepresentation.get(from: propertyListArray)
    }
    
    @inlinable
    public static func set(_ dictionaryKey: String, to value: Self, in propertyListDictionary: inout [String: Any]) {
        var propertyListArray: [Any] = []
        
        propertyListArray.reserveCapacity(value.capacity)
        
        Element.persistentKeyValueRepresentation.set(value, to: &propertyListArray)
        
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
    
    @inlinable
    public static func set(_ userDefaultsKey: String, to value: Self, in userDefaults: UserDefaults) {
        var propertyListArray: [Any] = []
        
        propertyListArray.reserveCapacity(value.capacity)
        
        Element.persistentKeyValueRepresentation.set(value, to: &propertyListArray)
        
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
    
    @available(watchOS 9.0, *)
    @inlinable
    public static func set(
        _ ubiquitousStoreKey: String,
        to value: Self,
        in ubiquitousStore: NSUbiquitousKeyValueStore
    ) {
        var propertyListArray: [Any] = []
        
        propertyListArray.reserveCapacity(value.capacity)
        
        Element.persistentKeyValueRepresentation.set(value, to: &propertyListArray)
        
        ubiquitousStore.set(propertyListArray, forKey: ubiquitousStoreKey)
    }
}
