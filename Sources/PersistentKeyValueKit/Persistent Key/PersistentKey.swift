//
//  PersistentKey.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 3/28/22.
//

import Foundation

/// A key for a value in a ``PersistentKeyValueStore``.
///
/// Define reusable keys as static members on ``PersistentKeyProtocol`` so call sites can use leading-dot syntax across
/// stores, property wrappers, observation APIs, and migrations:
///
/// ```swift
/// extension PersistentKeyProtocol where Self == PersistentKey<Int> {
///     static var launchCount: Self {
///         Self("LaunchCount", defaultValue: 0)
///     }
/// }
///
/// let launchCount = userDefaults.get(.launchCount)
/// userDefaults.set(.launchCount, to: launchCount + 1)
/// ```
public struct PersistentKey<Value>: Identifiable where Value: Sendable {
    /// The default value for the key.
    /// 
    /// This value is returned when the key is not present.
    public let defaultValue: Value

    /// The unique identifier for the key.
    ///
    /// This value must be unique across all keys in a given ``PersistentKeyValueStore``.
    public let id: String
    
    /// The representation of the key-value pair in the ``PersistentKeyValueStore``.
    public let representation: any PersistentKeyValueRepresentation<Value>
    
    // MARK: Public Initialization
    
    /// Creates a new key with the given identifier and default value.
    ///
    /// The key-value pair is represented by the default representation for `Value`.
    ///
    /// - Parameter id: The unique identifier for the key.
    /// - Parameter defaultValue: The default value for the key.
    @inlinable
    public init(
        _ id: String,
        defaultValue: Value
    ) where Value: KeyValuePersistible {
        self.id = id
        self.defaultValue = defaultValue
        
        representation = Value.persistentKeyValueRepresentation
    }
    
    /// Creates a new key with the given identifier, default value, and representation.
    /// 
    /// Use this initializer to supply a custom representation for this specific key instead of using the default
    /// representation for `Value`.
    ///
    /// - Parameter id: The unique identifier for the key.
    /// - Parameter defaultValue: The default value for the key.
    /// - Parameter representation: The representation used to persist the value.
    @inlinable
    public init(
        _ id: String,
        defaultValue: Value,
        representation: some PersistentKeyValueRepresentation<Value>
    ) {
        self.id = id
        self.defaultValue = defaultValue
        self.representation = representation
    }
    
    /// Creates a new key with the given identifier, default value, and representation.
    ///
    /// Use this initializer to supply a custom representation for this specific key instead of using the default
    /// representation for `Value?`.
    ///
    /// - Parameter id: The unique identifier for the key.
    /// - Parameter defaultValue: The default value for the key.
    /// - Parameter representation: The representation used to persist the value.
    @inlinable
    public init<Unwrapped>(
        _ id: String,
        defaultValue: Value,
        representation: some PersistentKeyValueRepresentation<Unwrapped>
    ) where Value == Optional<Unwrapped> {
        self.id = id
        self.defaultValue = defaultValue
        self.representation = representation.optionalRepresentation
    }
}

// MARK: - PersistentKeyProtocol Extension

extension PersistentKey: PersistentKeyProtocol {
    // MARK: Interfacing with User Defaults

    @inlinable
    public func get(from userDefaults: UserDefaults) -> Value {
        representation.get(id, from: userDefaults) ?? defaultValue
    }
    
    @inlinable
    public func remove(from userDefaults: UserDefaults) {
        userDefaults.removeObject(forKey: id)
    }
    
    @inlinable
    public func set(to newValue: Value, in userDefaults: UserDefaults) {
        representation.set(id, to: newValue, in: userDefaults)
    }

    // MARK: Interfacing with Ubiquitous Key-Value Store
    
    @available(watchOS 9.0, *)
    @inlinable
    public func get(from ubiquitousStore: NSUbiquitousKeyValueStore) -> Value {
        representation.get(id, from: ubiquitousStore) ?? defaultValue
    }
    
    @available(watchOS 9.0, *)
    @inlinable
    public func remove(from ubiquitousStore: NSUbiquitousKeyValueStore) {
        ubiquitousStore.removeObject(forKey: id)
    }
    
    @available(watchOS 9.0, *)
    @inlinable
    public func set(to newValue: Value, in ubiquitousStore: NSUbiquitousKeyValueStore) {
        representation.set(id, to: newValue, in: ubiquitousStore)
    }
}

// MARK: - Conditional Equatable Extension

extension PersistentKey: Equatable where Value: Equatable {
    // MARK: Public Static Interface
    
    /// Returns whether two keys have equal default values and literally identical identifiers.
    ///
    /// Identifiers are compared by their UTF-16 code units, as Foundation stores compare keys, so canonically
    /// equivalent spellings, such as composed and decomposed "café", are different keys even though they are equal as
    /// Swift strings. ``InMemoryPersistentKeyValueStore`` stores such spellings in one entry.
    @inlinable
    public static func == (lhs: PersistentKey<Value>, rhs: PersistentKey<Value>) -> Bool {
        lhs.defaultValue == rhs.defaultValue && LiteralKeyID.match(lhs.id, rhs.id)
    }
}

// MARK: - Conditional Hashable Extension

extension PersistentKey: Hashable where Value: Hashable {
    // MARK: Public Instance Interface
    
    /// Hashes the default value and the UTF-16 code units of the identifier, so keys that are equal hash equally.
    @inlinable
    public func hash(into hasher: inout Hasher) {
        hasher.combine(defaultValue)

        LiteralKeyID.hash(id, into: &hasher)
    }
}
