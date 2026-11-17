//
//  Data+KeyValuePersistible.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 4/13/24.
//

import Foundation

// MARK: - KeyValuePersistible Extension

extension Data {
    // MARK: Public Static Interface
    
    @inlinable
    public static var persistentKeyValueRepresentation: some PersistentKeyValueRepresentation<Self> {
        PrimitivePersistentKeyValueRepresentation()
    }
}

// MARK: - PrimitiveKeyValuePersistible Extension

extension Data: PrimitiveKeyValuePersistible {
    // MARK: Checked Conversion

    public static func decode(storageObject: Any, format: PersistentKeyValueStorageFormat) throws -> Data {
        try checkedStorageValue(from: storageObject)
    }

    public func encode(format: PersistentKeyValueStorageFormat) throws -> Any? {
        self
    }

    // MARK: Interfacing with Property List Array

    // Values of this type are property-list objects, so containers store and cast them directly.
    @inlinable
    public static func get(from propertyListArray: [Any]) -> [Self]? {
        propertyListArray as? [Self]
    }

    @inlinable
    public static func set(_ values: [Self], to propertyListArray: inout [Any]) {
        propertyListArray = values
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

    // MARK: Interfacing with User Defaults
    
    @inlinable
    public static func get(_ userDefaultsKey: String, from userDefaults: UserDefaults) -> Self? {
        userDefaults.data(forKey: userDefaultsKey)
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
        ubiquitousStore.data(forKey: ubiquitousStoreKey)
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
