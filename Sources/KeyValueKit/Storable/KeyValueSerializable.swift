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
    /// - Parameter storage: The closure that provides access to the value that should be deserialized, if it exists.
    /// - Returns: A new instance that is representative of the given value, if it exists and if possible.
    static func decode(from storage: @autoclosure () -> Serialization?) -> Self?
    
    /// Serializes this value.
    ///
    /// - Returns: The serialized version of this value.
    func encodeForStorage() -> Serialization
}

// MARK: - Novel Implementation

extension KeyValueSerializable {
    // MARK: Serializing & Deserializing
    
    @inlinable
    public static func decode<Key>(
        for key: Key,
        from storage: @autoclosure () -> Serialization?
    ) -> Self where Key: StorageKeyProtocol, Key.Value == Self {
        decode(from: storage()) ?? key.defaultValue
    }
}
