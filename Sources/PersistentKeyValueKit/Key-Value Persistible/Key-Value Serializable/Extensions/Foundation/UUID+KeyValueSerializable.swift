//
//  UUID+KeyValueSerializable.swift
//  KeyValueKit
//
//  Created by Kyle Hughes on 2/26/24.
//

import Foundation

// MARK: - KeyValueSerializable Extension

extension UUID: KeyValueSerializable {
    // MARK: Public Typealiases
    
    /// The type that this value can be serialized to and deserialized from.
    public typealias Serialization = String
    
    // MARK: Serializing & Deserializing
    
    /// Creates a new instance by deserializing from the given serialization.
    ///
    /// - Parameter serialization: The closure that provides access to the serialization that should be deserialized, 
    ///   if it exists.
    /// - Returns: A new instance that is representative of the serialization, if it exists and if possible.
    @inlinable
    public static func deserialize(from serialization: @autoclosure () -> Serialization?) -> Self? {
        guard let serialization = serialization() else {
            return nil
        }
        
        return UUID(uuidString: serialization)
    }
    
    /// Serializes this value.
    ///
    /// - Returns: The serialization of this value.
    @inlinable
    public func serialize() -> Serialization {
        uuidString
    }
}
