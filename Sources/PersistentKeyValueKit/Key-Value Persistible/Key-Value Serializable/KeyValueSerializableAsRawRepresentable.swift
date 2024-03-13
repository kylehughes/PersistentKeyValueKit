//
//  KeyValueSerializableAsRawRepresentable.swift
//  KeyValueKit
//
//  Created by Kyle Hughes on 2/25/24.
//

import Foundation

public protocol KeyValueSerializableAsRawRepresentable: KeyValueSerializable, RawRepresentable
where
    RawValue: KeyValueSerializable,
    Serialization == RawValue,
    Serialization == RawValue.Serialization
{
    // NO-OP
}

// MARK: - KeyValuePersistible Implementation

extension KeyValueSerializableAsRawRepresentable {
    // MARK: Converting to and from KeyValuePersistible Value
    
    /// Creates a new instance by deserializing from the given serialization.
    ///
    /// - Parameter serialization: The closure that provides access to the serialization that should be deserialized, 
    ///   if it exists.
    /// - Returns: A new instance that is representative of the serialization, if it exists and if possible.
    @inlinable
    public static func deserialize(from serialization: @autoclosure () -> Serialization?) -> Self? {
        guard let rawValue = RawValue.deserialize(from: serialization()), let value = Self(rawValue: rawValue) else {
            return nil
        }
        
        return value
    }
    
    /// Serializes this value.
    ///
    /// - Returns: The serialization of this value.
    @inlinable
    public func serialize() -> Serialization {
        rawValue.serialize()
    }
}
