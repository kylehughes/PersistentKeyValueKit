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

// MARK: - BuiltInScalarPrimitive Extension

extension URL: BuiltInScalarPrimitive {}

// MARK: - PrimitiveKeyValuePersistible Extension

extension URL: PrimitiveKeyValuePersistible {
    /// Decodes a `URL` from a stored object for the given storage format.
    ///
    /// - For ``PersistentKeyValueStorageFormat/propertyList``, expects a `String` that `URL(string:)` accepts.
    /// - For ``PersistentKeyValueStorageFormat/ubiquitousKeyValueStore``, accepts a `String` that `URL(string:)`
    ///   accepts, or a legacy `URL` object.
    ///
    /// These strings are not required to be absolute. ``encode(format:)`` writes `absoluteString`, which is a relative
    /// reference for a URL without a scheme or base URL, and decoding accepts it so such values read back.
    /// - For ``PersistentKeyValueStorageFormat/userDefaults``, accepts `NSKeyedArchiver` `Data`, a tilde-abbreviated
    ///   file path `String`, or a `URL` object, matching `UserDefaults.url(forKey:)`. A path decodes to the file URL
    ///   that `url(forKey:)` returns, and a path it reads as `nil`, such as an empty string, throws
    ///   ``PersistentKeyValueConversionError/invalidStorageValue``.
    public static func decode(
        storageObject: Any,
        format: PersistentKeyValueStorageFormat
    ) throws -> URL {
        if format == .ubiquitousKeyValueStore, let value = storageObject as? URL {
            return value
        }
        if format == .userDefaults {
            if let value = storageObject as? URL {
                return value
            }
            if let data = storageObject as? Data {
                let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
                unarchiver.decodingFailurePolicy = .setErrorAndReturn
                defer {
                    unarchiver.finishDecoding()
                }
                guard let value = unarchiver.decodeObject(of: NSURL.self, forKey: NSKeyedArchiveRootObjectKey)
                else {
                    throw PersistentKeyValueConversionError.invalidStorageValue
                }
                return value as URL
            }
            // `UserDefaults.url(forKey:)` reads a path through `NSURL.fileURL(withPath:)`, which differs from
            // `URL(fileURLWithPath:)` and returns `nil`, despite its non-optional signature, for a path it rejects, such
            // as an empty one. `perform(_:with:)` returns that result as an optional.
            guard
                let path = storageObject as? String,
                let value = NSURL.perform(
                    #selector(NSURL.fileURL(withPath:)),
                    with: (path as NSString).expandingTildeInPath
                )?.takeUnretainedValue() as? NSURL
            else {
                throw PersistentKeyValueConversionError.invalidStorageValue
            }
            return value as URL
        }
        guard let string = storageObject as? String, let value = URL(string: string) else {
            throw PersistentKeyValueConversionError.invalidStorageValue
        }
        return value
    }

    /// Encodes the `URL` for the given storage format.
    ///
    /// Encodes as `absoluteString` for ``PersistentKeyValueStorageFormat/propertyList`` and
    /// ``PersistentKeyValueStorageFormat/ubiquitousKeyValueStore``; a relative URL without a base URL encodes as its
    /// relative reference. For
    /// ``PersistentKeyValueStorageFormat/userDefaults``, encodes file URLs as tilde-abbreviated paths and non-file
    /// URLs as secure-coded `NSKeyedArchiver` data, matching `UserDefaults.set(_:forKey:)`.
    ///
    /// A file URL whose path cannot reproduce its `absoluteString`, such as one with a host or a non-existent
    /// directory's trailing slash, throws ``PersistentKeyValueConversionError/encodingFailed`` for
    /// ``PersistentKeyValueStorageFormat/userDefaults``. This applies wherever the URL is encoded for `UserDefaults`,
    /// including through `Optional` and proxy representations, so migration to `UserDefaults` fails at
    /// ``PersistentKeyMigrationReport/FailureStage/prepare`` before any store is modified, and
    /// `UserDefaults.register(_:)` skips such a default value. Ordinary `UserDefaults` writes of such a URL keep
    /// Foundation's behavior and store the path.
    public func encode(format: PersistentKeyValueStorageFormat) throws -> Any? {
        switch format {
        case .propertyList, .ubiquitousKeyValueStore:
            return absoluteString
        case .userDefaults:
            if isFileURL {
                let path = (path as NSString).abbreviatingWithTildeInPath
                // The path drops a host and a trailing slash that later relative resolution depends on, and
                // `url(forKey:)` reads an empty path as `nil`.
                guard
                    let storedURL = try? Self.decode(storageObject: path, format: .userDefaults),
                    storedURL.absoluteString == absoluteString
                else {
                    throw PersistentKeyValueConversionError.encodingFailed
                }

                return path
            }
            return try NSKeyedArchiver.archivedData(withRootObject: self, requiringSecureCoding: true)
        }
    }

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
        propertyListArray = values.map(\.absoluteString)
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
        let object = ubiquitousStore.object(forKey: ubiquitousStoreKey)
        if let value = object as? Self {
            return value
        }
        guard let string = object as? String else {
            return nil
        }
        return URL(string: string)
    }
    
    @available(watchOS 9.0, *)
    @inlinable
    public static func set(
        _ ubiquitousStoreKey: String,
        to value: Self,
        in ubiquitousStore: NSUbiquitousKeyValueStore
    ) {
        ubiquitousStore.set(value.absoluteString, forKey: ubiquitousStoreKey)
    }
}
