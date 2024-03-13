//
//  KeyValueSerializable.swift
//  KeyValueKit
//
//  Created by Kyle Hughes on 2/25/24.
//

import Foundation

/// A type that can be serialized and deserialized to another type, with the intention of being stored in a
/// ``PersistentKeyValueStore``.
public protocol KeyValueSerializable<Serialization> {
    // MARK: Associated Types
    
    /// The type that this value can be serialized to and deserialized from.
    associatedtype Serialization
    
    // MARK: Serializing & Deserializing

    /// Creates a new instance by deserializing from the given serialization.
    ///
    /// - Parameter serialization: The closure that provides access to the serialization that should be deserialized, 
    ///   if it exists.
    /// - Returns: A new instance that is representative of the serialization, if it exists and if possible.
    static func deserialize(from serialization: @autoclosure () -> Serialization?) -> Self?
    
    /// Serializes this value.
    ///
    /// - Returns: The serialization of this value.
    func serialize() -> Serialization
}

// MARK: - Novel Implementation

extension KeyValueSerializable {
    // MARK: Serializing & Deserializing
    
    /// Creates a new instance by deserializing from the given serialization, or returns the default value if the
    /// serialization cannot be deserialized.
    ///
    /// - Parameter key: The key that the value is associated with.
    /// - Parameter serialization: The closure that provides access to the serialization that should be deserialized, 
    ///   if it exists.
    /// - Returns: A new instance that is representative of the serialization, if it exists and if possible, or the
    ///   default value if the serialization cannot be deserialized.
    @inlinable
    public static func deserialize<Key>(
        for key: Key,
        from serialization: @autoclosure () -> Serialization?
    ) -> Self where Key: PersistentKeyProtocol, Key.Value == Self {
        deserialize(from: serialization()) ?? key.defaultValue
    }
}
