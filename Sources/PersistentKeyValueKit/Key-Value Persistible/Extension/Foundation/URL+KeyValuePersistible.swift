//
//  URL+KeyValuePersistible.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 4/13/24.
//

import Foundation

// MARK: - KeyValuePersistible Extension

extension URL {
    // MARK: Public Static Interface
    
    @inlinable
    public static var persistentKeyValueRepresentation: some PersistentKeyValueRepresentation<Self> {
        PrimitivePersistentKeyValueRepresentation()
    }
}

// MARK: - PrimitiveKeyValuePersistible Extension

extension URL: PrimitiveKeyValuePersistible {
    // MARK: Interfacing with Property List Array
    
    public static func get(from propertyListArray: [Any]) -> [Self]? {
        var originalArray: [Self] = []
        
        originalArray.reserveCapacity(propertyListArray.count)
        
        for value in propertyListArray {
            guard let storedValue = value as? String, let value = URL(string: storedValue) else {
                return nil
            }
            
            originalArray.append(value)
        }
        
        return originalArray
    }
    
    @inlinable
    public static func set(_ values: [Self], to propertyListArray: inout [Any]) {
        propertyListArray.reserveCapacity(propertyListArray.count + values.count)

        for value in values {
            propertyListArray.append(value.absoluteString)
        }
    }
    
    // MARK: Interfacing with Property List Dictionary
    
    @inlinable
    public static func get(_ dictionaryKey: String, from propertyListDictionary: [String: Any]) -> Self? {
        guard
            let storedValue = propertyListDictionary[dictionaryKey] as? String,
            let value = URL(string: storedValue)
        else {
            return nil
        }
        
        return value
    }
    
    @inlinable
    public static func set(_ dictionaryKey: String, to value: Self, in propertyListDictionary: inout [String: Any]) {
        propertyListDictionary[dictionaryKey] = value.absoluteString
    }
    
    // MARK: Interfacing with User Defaults
    
    @inlinable
    public static func get(_ userDefaultsKey: String, from userDefaults: UserDefaults) -> Self? {
        let object = userDefaults.object(forKey: userDefaultsKey)

        // Launch arguments live in `UserDefaults.argumentDomain` as strings, even when the key models a typed value.
        // Scope parsing to that domain and require a scheme so ordinary persisted strings do not become URLs, and so
        // `url(forKey:)` keeps Foundation's file URL behavior for stored values.
        if let stringValue = userDefaults.argumentDomainString(forKey: userDefaultsKey, visibleObject: object) {
            guard
                let value = URL(string: stringValue.trimmingCharacters(in: .whitespacesAndNewlines)),
                value.scheme != nil
            else {
                return nil
            }

            return value
        }

        return userDefaults.url(forKey: userDefaultsKey)
    }
    
    @inlinable
    public static func set(_ userDefaultsKey: String, to value: Self, in userDefaults: UserDefaults) {
        userDefaults.set(value, forKey: userDefaultsKey)
    }
    
    // MARK: Interfacing with Ubiquitous Key-Value Store
    
    @available(watchOS 9.0, *)
    @inlinable
    public static func get(
        _ ubiquitousStoreKey: String,
        from ubiquitousStore: NSUbiquitousKeyValueStore
    ) -> Self? {
        ubiquitousStore.object(forKey: ubiquitousStoreKey) as? Self
    }
    
    @available(watchOS 9.0, *)
    @inlinable
    public static func set(
        _ ubiquitousStoreKey: String,
        to value: Self,
        in ubiquitousStore: NSUbiquitousKeyValueStore
    ) {
        ubiquitousStore.set(value, forKey: ubiquitousStoreKey)
    }
}
