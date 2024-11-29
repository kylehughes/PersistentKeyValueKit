//
//  PersistentKey.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 3/28/22.
//

import Foundation

/// A key for a value in a ``PersistentKeyValueStore``.
///
/// It is recommended to use the static accessor pattern to define and access keys. This pattern allows you to define
/// keys in common locations and access them anywhere in a type-safe manner. The APIs are designed to be as ergonomic
/// as possible for this pattern.
///
/// e.g.
///
/// ```swift
/// extension PersistentKeyProtocol where Self == PersistentKey<Date> {
///     static var mostRecentLaunchDate: Self {
///         Self("MostRecentLaunchDate", defaultValue: .distantPast)
///     }
/// }
/// …
/// userDefaults.set(.mostRecentLaunchDate, to: .now)
/// …
/// guard userDefaults.get(.mostRecentLaunchDate) < firstOfMonth else …
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
    /// The key-value pair is represented by the default representation for ``Value``.
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
    /// representation for ``Value``.
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
    /// representation for ``Value?``.
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
    
    @inlinable
    public static func == (lhs: PersistentKey<Value>, rhs: PersistentKey<Value>) -> Bool {
        lhs.defaultValue == rhs.defaultValue && lhs.id == rhs.id
    }
}

// MARK: - Conditional Hashable Extension

extension PersistentKey: Hashable where Value: Hashable {
    // MARK: Public Instance Interface
    
    @inlinable
    public func hash(into hasher: inout Hasher) {
        hasher.combine(defaultValue)
        hasher.combine(id)
    }
}
