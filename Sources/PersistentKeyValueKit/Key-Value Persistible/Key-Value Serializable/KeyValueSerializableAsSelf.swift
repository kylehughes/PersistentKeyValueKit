//
//  KeyValueSerializableAsSelf.swift
//  KeyValueKit
//
//  Created by Kyle Hughes on 2/25/24.
//

import Foundation

public protocol KeyValueSerializableAsSelf: KeyValueSerializable 
where
    Serialization == Self
{
    // NO-OP
}

// MARK: - KeyValueSerializable Extension

extension KeyValueSerializableAsSelf {
    // MARK: Serializing & Deserializing
    
    /// Creates a new instance by deserializing from the given serialization.
    ///
    /// - Parameter serialization: The closure that provides access to the serialization that should be deserialized, 
    ///   if it exists.
    /// - Returns: A new instance that is representative of the serialization, if it exists and if possible.
    @inlinable
    public static func deserialize(from serialization: @autoclosure () -> Serialization?) -> Self? {
        serialization()
    }
    
    /// Serializes this value.
    ///
    /// - Returns: The serialization of this value.
    @inlinable
    public func serialize() -> Serialization {
        self
    }
}
