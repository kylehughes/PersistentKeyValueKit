//
//  String+KeyValuePersistible.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 4/13/24.
//

import Foundation

// MARK: - KeyValuePersistible Extension

extension String: KeyValuePersistible {
    // MARK: Public Static Interface
    
    @inlinable
    public static var persistentKeyValueRepresentation: some PersistentKeyValueRepresentation<Self> {
        PrimitivePersistentKeyValueRepresentation()
    }
}

// MARK: - BuiltInScalarPrimitive Extension

extension String: BuiltInScalarPrimitive {}

// MARK: - PrimitiveKeyValuePersistible Extension

extension String: PrimitiveKeyValuePersistible {
    // MARK: Checked Conversion

    /// Decodes a stored string.
    ///
    /// In the ``PersistentKeyValueStorageFormat/userDefaults`` and
    /// ``PersistentKeyValueStorageFormat/ubiquitousKeyValueStore`` formats, a stored number also decodes as its
    /// `stringValue`, as `UserDefaults.string(forKey:)`, `NSUbiquitousKeyValueStore.string(forKey:)`, and an ordinary
    /// read return it. A Boolean decodes as `"1"` or `"0"`. In the ``PersistentKeyValueStorageFormat/propertyList``
    /// format, only a stored string decodes. `Optional<String>`, `String`-backed `RawRepresentable`,
    /// `LosslessStringConvertible`, and proxy keys over `String` inherit this behavior.
    public static func decode(storageObject: Any, format: PersistentKeyValueStorageFormat) throws -> String {
        if format != .propertyList, let number = storageObject as? NSNumber {
            return number.stringValue
        }

        return try checkedStorageValue(from: storageObject)
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
        userDefaults.string(forKey: userDefaultsKey)
    }
    
    @inlinable
    public static func set(_ userDefaultsKey: String, to value: Self, in userDefaults: UserDefaults) {
        userDefaults.set(value, forKey: userDefaultsKey)
    }
    
    // MARK: Interfacing with Ubiquitous Key-Value Store
    
    @inlinable
    public static func get(
        _ ubiquitousStoreKey: String,
        from ubiquitousStore: NSUbiquitousKeyValueStore
    ) -> Self? {
        ubiquitousStore.string(forKey: ubiquitousStoreKey)
    }
    
    @inlinable
    public static func set(
        _ ubiquitousStoreKey: String,
        to value: Self,
        in ubiquitousStore: NSUbiquitousKeyValueStore
    ) {
        ubiquitousStore.set(value, forKey: ubiquitousStoreKey)
    }
}
