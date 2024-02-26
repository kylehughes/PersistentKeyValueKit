//
//  Storable.swift
//  KeyValueKit
//
//  Created by Kyle Hughes on 3/29/22.
//

import Foundation

/// A type that can be a value in key-value storage implementations that conform to ``Storage``.
public protocol Storable {
    // MARK: Associated Types
    
    /// The underlying type that values of the ``Storable`` type are stored as. The ``Storable`` type is encoded to and
    /// decoded from this type.
    associatedtype StorableValue
    
    // MARK: Converting to and from Storable Value

    /// Creates a new instance by decoding from the given storable value.
    ///
    /// - Parameter storage: The closure that provides access to the value that should be decoded, if it exists.
    /// - Returns: A new instance that is representative of the given storable value, if it exists and if possible.
    static func decode(from storage: @autoclosure () -> StorableValue?) -> Self?
    
    /// Encodes this value so that it is suitable for storage.
    ///
    /// - Returns: The encoded version of this value that can be stored.
    func encodeForStorage() -> StorableValue
    
    // MARK: Interfacing with User Defaults
    
    static func extract(_ userDefaultsKey: String, from userDefaults: UserDefaults) -> StorableValue?
    
    func store(_ value: StorableValue, as userDefaultsKey: String, in userDefaults: UserDefaults)
    
    #if !os(watchOS)
    
    // MARK: Interfacing with Ubiquitous Key-Value Store
    
    static func extract(_ ubiquitousStoreKey: String, from ubiquitousStore: NSUbiquitousKeyValueStore) -> StorableValue?
    
    func store(_ value: StorableValue, as ubiquitousStoreKey: String, in ubiquitousStore: NSUbiquitousKeyValueStore)
    
    #endif
}

// MARK: - Default Implementation

extension Storable {
    // MARK: Interfacing with User Defaults
    
    @inlinable
    public static func extract(_ userDefaultsKey: String, from userDefaults: UserDefaults) -> StorableValue? {
        userDefaults.object(forKey: userDefaultsKey) as? StorableValue
    }
    
    @inlinable
    public func store(_ value: StorableValue, as userDefaultsKey: String, in userDefaults: UserDefaults) {
        userDefaults.set(value, forKey: userDefaultsKey)
    }
    
    #if !os(watchOS)
    
    // MARK: Interfacing with Ubiquitous Key-Value Store
    
    @inlinable
    public static func extract(
        _ ubiquitousStoreKey: String,
        from ubiquitousStore: NSUbiquitousKeyValueStore
    ) -> StorableValue? {
        ubiquitousStore.object(forKey: ubiquitousStoreKey) as? StorableValue
    }
    
    @inlinable
    public func store(
        _ value: StorableValue,
        as ubiquitousStoreKey: String,
        in ubiquitousStore: NSUbiquitousKeyValueStore
    ) {
        ubiquitousStore.set(value, forKey: ubiquitousStoreKey)
    }
    
    #endif
}

// MARK: - Default Implementation for Types Whose Storable Value is Self

extension Storable where StorableValue == Self {
    // MARK: Converting to and from Storable Value
    
    @inlinable
    public static func decode(from storage: @autoclosure () -> StorableValue?) -> Self? {
        storage()
    }
    
    @inlinable
    public func encodeForStorage() -> StorableValue {
        self
    }
}

// MARK: - Novel Implementation

extension Storable {
    // MARK: Converting to and from Storable Value
    
    @inlinable
    public static func decode<Key>(
        for key: Key,
        from storage: @autoclosure () -> StorableValue?
    ) -> Self where Key: StorageKeyProtocol, Key.Value == Self {
        decode(from: storage()) ?? key.defaultValue
    }
    
    // MARK: Interfacing with User Defaults
    
    @inlinable
    public static func extract<Key>(
        _ key: Key,
        from userDefaults: UserDefaults
    ) -> StorableValue? where Key: StorageKeyProtocol {
        extract(key.id, from: userDefaults)
    }
    
    #if !os(watchOS)
    
    // MARK: Interfacing with Ubiquitous Key-Value Store
    
    @inlinable
    public static func extract<Key>(
        _ key: Key,
        from ubiquitousStore: NSUbiquitousKeyValueStore
    ) -> StorableValue? where Key: StorageKeyProtocol {
        extract(key.id, from: ubiquitousStore)
    }
    
    #endif
}

// MARK: - Extension for Bool

extension Bool: Storable {
    // MARK: Public Typealiases
    
    public typealias StorableValue = Self

    // MARK: Interfacing With User Defaults
    
    @inlinable
    public static func extract(_ userDefaultsKey: String, from userDefaults: UserDefaults) -> StorableValue? {
        // We use the default implementation with `object(forKey)` so that we can differentiate a `nil` value from
        // a `false` value.
        userDefaults.object(forKey: userDefaultsKey) as? StorableValue
    }
    
    @inlinable
    public func store(_ value: StorableValue, as userDefaultsKey: String, in userDefaults: UserDefaults) {
        userDefaults.set(value, forKey: userDefaultsKey)
    }
    
    #if !os(watchOS)
    
    @inlinable
    public static func extract(
        _ ubiquitousStoreKey: String,
        from ubiquitousStore: NSUbiquitousKeyValueStore
    ) -> StorableValue? {
        // We use the default implementation with `object(forKey)` so that we can differentiate a `nil` value from
        // a `false` value.
        ubiquitousStore.object(forKey: ubiquitousStoreKey) as? StorableValue
    }
    
    @inlinable
    public func store(
        _ value: StorableValue,
        as ubiquitousStoreKey: String,
        in ubiquitousStore: NSUbiquitousKeyValueStore
    ) {
        ubiquitousStore.set(value, forKey: ubiquitousStoreKey)
    }
    
    #endif
}

// MARK: - Extension for Data

extension Data: Storable {
    // MARK: Public Typealiases
    
    public typealias StorableValue = Self

    // MARK: Interfacing With User Defaults

    @inlinable
    public static func extract(_ userDefaultsKey: String, from userDefaults: UserDefaults) -> StorableValue? {
        userDefaults.data(forKey: userDefaultsKey)
    }
    
    #if !os(watchOS)
    
    @inlinable
    public static func extract(
        _ ubiquitousStoreKey: String,
        from ubiquitousStore: NSUbiquitousKeyValueStore
    ) -> StorableValue? {
        ubiquitousStore.data(forKey: ubiquitousStoreKey)
    }
    
    @inlinable
    public func store(
        _ value: StorableValue,
        as ubiquitousStoreKey: String,
        in ubiquitousStore: NSUbiquitousKeyValueStore
    ) {
        ubiquitousStore.set(value, forKey: ubiquitousStoreKey)
    }
    
    #endif
}

// MARK: - Extension for Date

extension Date: Storable {
    // MARK: Public Typealiases
    
    public typealias StorableValue = TimeInterval
    
    // MARK: Converting to and from Storable Value
    
    @inlinable
    public static func decode(from storage: @autoclosure () -> StorableValue?) -> Self? {
        guard let storableValue = storage() else {
            return nil
        }
        
        return Date(timeIntervalSince1970: storableValue)
    }
    
    @inlinable
    public func encodeForStorage() -> TimeInterval {
        timeIntervalSince1970
    }
}

// MARK: - Extension for Double

extension Double: Storable {
    // MARK: Public Typealiases
    
    public typealias StorableValue = Self

    // MARK: Interfacing With User Defaults
    
    @inlinable
    public static func extract(_ userDefaultsKey: String, from userDefaults: UserDefaults) -> StorableValue? {
        // We use the default implementation with `object(forKey)` so that we can differentiate a `nil` value from
        // a 0 value.
        userDefaults.object(forKey: userDefaultsKey) as? StorableValue
    }

    @inlinable
    public func store(_ value: StorableValue, as userDefaultsKey: String, in userDefaults: UserDefaults) {
        userDefaults.set(value, forKey: userDefaultsKey)
    }
    
    #if !os(watchOS)

    @inlinable
    public static func extract(
        _ ubiquitousStoreKey: String,
        from ubiquitousStore: NSUbiquitousKeyValueStore
    ) -> StorableValue? {
        // We use the default implementation with `object(forKey)` so that we can differentiate a `nil` value from
        // a 0 value.
        ubiquitousStore.object(forKey: ubiquitousStoreKey) as? StorableValue
    }
    
    @inlinable
    public func store(
        _ value: StorableValue,
        as ubiquitousStoreKey: String,
        in ubiquitousStore: NSUbiquitousKeyValueStore
    ) {
        ubiquitousStore.set(value, forKey: ubiquitousStoreKey)
    }

    #endif
}

// MARK: - Extension for Float

extension Float: Storable {
    // MARK: Public Typealiases
    
    public typealias StorableValue = Self
    
    // MARK: Interfacing With User Defaults
    
    @inlinable
    public static func extract(_ userDefaultsKey: String, from userDefaults: UserDefaults) -> StorableValue? {
        // We use the default implementation with `object(forKey)` so that we can differentiate a `nil` value from
        // a 0 value.
        userDefaults.object(forKey: userDefaultsKey) as? StorableValue
    }
    
    @inlinable
    public func store(_ value: StorableValue, as userDefaultsKey: String, in userDefaults: UserDefaults) {
        userDefaults.set(value, forKey: userDefaultsKey)
    }
    
    #if !os(watchOS)

    @inlinable
    public static func extract(
        _ ubiquitousStoreKey: String,
        from ubiquitousStore: NSUbiquitousKeyValueStore
    ) -> StorableValue? {
        // We use the default implementation with `object(forKey)` so that we can differentiate a `nil` value from
        // a 0 value.
        ubiquitousStore.object(forKey: ubiquitousStoreKey) as? StorableValue
    }

    #endif
}

// MARK: - Extension for Int

extension Int: Storable {
    // MARK: Public Typealiases
    
    public typealias StorableValue = Self

    // MARK: Interfacing With User Defaults

    @inlinable
    public static func extract(_ userDefaultsKey: String, from userDefaults: UserDefaults) -> StorableValue? {
        // We use the default implementation with `object(forKey)` so that we can differentiate a `nil` value from
        // a 0 value.
        userDefaults.object(forKey: userDefaultsKey) as? StorableValue
    }
    
    @inlinable
    public func store(_ value: StorableValue, as userDefaultsKey: String, in userDefaults: UserDefaults) {
        userDefaults.set(value, forKey: userDefaultsKey)
    }
    
    #if !os(watchOS)

    @inlinable
    public static func extract(
        _ ubiquitousStoreKey: String,
        from ubiquitousStore: NSUbiquitousKeyValueStore
    ) -> StorableValue? {
        ubiquitousStore.object(forKey: ubiquitousStoreKey) as? StorableValue
    }

    #endif
}

// MARK: - Extension for String

extension String: Storable {
    // MARK: Public Typealiases
    
    public typealias StorableValue = Self
    
    // MARK: Converting to and from Storable Value
    
    @inlinable
    public static func decode(from storage: @autoclosure () -> StorableValue?) -> Self? {
        storage()
    }
    
    @inlinable
    public func encodeForStorage() -> StorableValue {
        self
    }

    // MARK: Interfacing With User Defaults

    @inlinable
    public static func extract(_ userDefaultsKey: String, from userDefaults: UserDefaults) -> StorableValue? {
        userDefaults.string(forKey: userDefaultsKey)
    }
    
    @inlinable
    public func store(_ value: StorableValue, as userDefaultsKey: String, in userDefaults: UserDefaults) {
        userDefaults.set(value, forKey: userDefaultsKey)
    }
    
    #if !os(watchOS)

    @inlinable
    public static func extract(
        _ ubiquitousStoreKey: String,
        from ubiquitousStore: NSUbiquitousKeyValueStore
    ) -> StorableValue? {
        ubiquitousStore.string(forKey: ubiquitousStoreKey)
    }
    
    @inlinable
    public func store(
        _ value: StorableValue,
        as ubiquitousStoreKey: String,
        in ubiquitousStore: NSUbiquitousKeyValueStore
    ) {
        ubiquitousStore.set(value, forKey: ubiquitousStoreKey)
    }

    #endif
}

// MARK: - Extension for [String]

extension Array: Storable where Element == String {
    // MARK: Public Typealiases
    
    public typealias StorableValue = Self

    // MARK: Interfacing With User Defaults

    @inlinable
    public static func extract(_ userDefaultsKey: String, from userDefaults: UserDefaults) -> StorableValue? {
        userDefaults.stringArray(forKey: userDefaultsKey)
    }
    
    #if !os(watchOS)

    
    @inlinable
    public static func extract(
        _ ubiquitousStoreKey: String,
        from ubiquitousStore: NSUbiquitousKeyValueStore
    ) -> StorableValue? {
        ubiquitousStore.array(forKey: ubiquitousStoreKey) as? StorableValue
    }
    
    @inlinable
    public func store(
        _ value: StorableValue,
        as ubiquitousStoreKey: String,
        in ubiquitousStore: NSUbiquitousKeyValueStore
    ) {
        ubiquitousStore.set(value, forKey: ubiquitousStoreKey)
    }

    #endif
}

// MARK: - Extension for URL

extension URL: Storable {
    // MARK: Public Typealiases
    
    public typealias StorableValue = Self

    // MARK: Interfacing With User Defaults

    @inlinable
    public static func extract(_ userDefaultsKey: String, from userDefaults: UserDefaults) -> StorableValue? {
        userDefaults.url(forKey: userDefaultsKey)
    }
    
    @inlinable
    public func store(_ value: StorableValue, as userDefaultsKey: String, in userDefaults: UserDefaults) {
        userDefaults.set(value, forKey: userDefaultsKey)
    }
    
    #if !os(watchOS)

    @inlinable
    public static func extract(
        _ ubiquitousStoreKey: String,
        from ubiquitousStore: NSUbiquitousKeyValueStore
    ) -> StorableValue? {
        ubiquitousStore.object(forKey: ubiquitousStoreKey) as? StorableValue
    }

    #endif
}

// MARK: - Extension for UUID

extension UUID: Storable {
    // MARK: Public Typealiases
    
    public typealias StorableValue = String
    
    // MARK: Converting to and from Storable Value
    
    @inlinable
    public static func decode(from storage: @autoclosure () -> StorableValue?) -> Self? {
        guard let storableValue = storage() else {
            return nil
        }
        
        return UUID(uuidString: storableValue)
    }
    
    @inlinable
    public func encodeForStorage() -> StorableValue {
        uuidString
    }
}

// MARK: - Extension for Optionals of Supported Types

extension Optional: Storable where Wrapped: Storable {
    // MARK: Public Typealiases
    
    public typealias StorableValue = Wrapped.StorableValue?
    
    // MARK: Converting to and From Storable Value
    
    @inlinable
    public static func decode(from storage: @autoclosure () -> StorableValue?) -> Self? {
        guard let wrappedStorableValue = storage(), let unwrappedStorableValue = wrappedStorableValue else {
            return nil
        }
        
        return Wrapped.decode(from: unwrappedStorableValue)
    }
    
    @inlinable
    public func encodeForStorage() -> StorableValue {
        switch self {
        case .none:
            return nil
        case let .some(wrapped):
            return wrapped.encodeForStorage()
        }
    }

    // MARK: Interfacing With User Defaults

    @inlinable
    public static func extract(_ userDefaultsKey: String, from userDefaults: UserDefaults) -> StorableValue? {
        Wrapped.extract(userDefaultsKey, from: userDefaults)
    }
    
    @inlinable
    public func store(_ value: StorableValue, as userDefaultsKey: String, in userDefaults: UserDefaults) {
        switch self {
        case .none:
            userDefaults.removeObject(forKey: userDefaultsKey)
        case let .some(wrapped):
            wrapped.store(wrapped.encodeForStorage(), as: userDefaultsKey, in: userDefaults)
        }
    }
    
    #if !os(watchOS)

    @inlinable
    public static func extract(
        _ ubiquitousStoreKey: String,
        from ubiquitousStore: NSUbiquitousKeyValueStore
    ) -> StorableValue? {
        Wrapped.extract(ubiquitousStoreKey, from: ubiquitousStore)
    }
    
    @inlinable
    public func store(
        _ value: StorableValue,
        as ubiquitousStoreKey: String,
        in ubiquitousStore: NSUbiquitousKeyValueStore
    ) {
        switch self {
        case .none:
            ubiquitousStore.removeObject(forKey: ubiquitousStoreKey)
        case let .some(wrapped):
            wrapped.store(wrapped.encodeForStorage(), as: ubiquitousStoreKey, in: ubiquitousStore)
        }
    }

    #endif
}
