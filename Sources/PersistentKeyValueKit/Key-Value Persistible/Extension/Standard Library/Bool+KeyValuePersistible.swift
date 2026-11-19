//
//  Bool+KeyValuePersistible.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 4/13/24.
//

import Foundation

// MARK: - KeyValuePersistible Extension

extension Bool {
    // MARK: Public Static Interface
    
    @inlinable
    public static var persistentKeyValueRepresentation: some PersistentKeyValueRepresentation<Self> {
        PrimitivePersistentKeyValueRepresentation()
    }
}

// MARK: - BuiltInScalarPrimitive Extension

extension Bool: BuiltInScalarPrimitive {}

// MARK: - PrimitiveKeyValuePersistible Extension

extension Bool: PrimitiveKeyValuePersistible {
    // MARK: Checked Conversion

    public static func decode(storageObject: Any, format: PersistentKeyValueStorageFormat) throws -> Bool {
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
        let object = userDefaults.object(forKey: userDefaultsKey)

        // We use `object(forKey:)` so that we can differentiate a `nil` value from a `false` value.
        if let value = object as? Self {
            return value
        }

        // Launch arguments live in `UserDefaults.argumentDomain` as strings, even when the key models a typed value.
        // Scope this coercion to that domain so ordinary persisted strings do not become booleans by accident.
        if let stringValue = userDefaults.argumentDomainString(forKey: userDefaultsKey, visibleObject: object) {
            switch stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "1", "true", "yes": return true
            case "0", "false", "no": return false
            default: return nil
            }
        }

        return nil
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
        // We use `object(forKey:)` so that we can differentiate a `nil` value from a `false` value.
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
