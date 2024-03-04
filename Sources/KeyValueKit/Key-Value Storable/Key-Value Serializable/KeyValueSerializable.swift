//
//  KeyValueSerializable.swift
//  KeyValueKit
//
//  Created by Kyle Hughes on 2/25/24.
//

import Foundation

public protocol KeyValueSerializable {
    // MARK: Associated Types
    
    associatedtype Serialization
    
    // MARK: Serializing & Deserializing

    /// Creates a new instance by deserializing from the given value.
    ///
    /// - Parameter serialization: The closure that provides access to the value that should be deserialized, if it
    ///   exists.
    /// - Returns: A new instance that is representative of the given value, if it exists and if possible.
    static func deserialize(from serialization: @autoclosure () -> Serialization?) -> Self?
    
    /// Serializes this value.
    ///
    /// - Returns: The serialized version of this value.
    func serialize() -> Serialization
}

// MARK: - Novel Implementation

extension KeyValueSerializable {
    // MARK: Serializing & Deserializing
    
    @inlinable
    public static func deserialize<Key>(
        for key: Key,
        from serialization: @autoclosure () -> Serialization?
    ) -> Self where Key: StorageKeyProtocol, Key.Value == Self {
        deserialize(from: serialization()) ?? key.defaultValue
    }
}
