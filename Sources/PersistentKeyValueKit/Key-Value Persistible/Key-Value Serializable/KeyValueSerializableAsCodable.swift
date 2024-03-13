//
//  KeyValueSerializableAsCodable.swift
//  KeyValueKit
//
//  Created by Kyle Hughes on 2/25/24.
//

import Foundation

public protocol KeyValueSerializableAsCodable: Codable, KeyValueSerializable
where
    Serialization == String
{
    // MARK: Static Interface
    
    /// The decoder to use when deserializing values.
    static var decoder: JSONDecoder { get }

    /// The encoder to use when serializing values.
    static var encoder: JSONEncoder { get }
}

// MARK: - KeyValueSerializable Implementation

extension KeyValueSerializableAsCodable {
    // MARK: Converting to and from KeyValueSerializable Value
    
    /// Creates a new instance by deserializing from the given serialization.
    ///
    /// - Parameter serialization: The closure that provides access to the serialization that should be deserialized, 
    ///   if it exists.
    /// - Returns: A new instance that is representative of the serialization, if it exists and if possible.
    @inlinable
    public static func deserialize(from serialization: @autoclosure () -> Serialization?) -> Self? {
        guard
            let jsonString = serialization(),
            let json = jsonString.data(using: .utf8),
            let value = try? decoder.decode(Self.self, from: json)
        else {
            return nil
        }
        
        return value
    }
    
    /// Serializes this value.
    ///
    /// - Returns: The serialization of this value.
    @inlinable
    public func serialize() -> Serialization {
        guard let data = try? Self.encoder.encode(self), let string = String(data: data, encoding: .utf8) else {
            fatalError("Unable to encode to JSON")
        }
        
        return string
    }
}

// MARK: - Default Implementation

extension KeyValueSerializableAsCodable {
    // MARK: Public Static Interface
    
    /// The decoder to use when deserializing values.
    @inlinable
    public static var decoder: JSONDecoder {
        JSONDecoder()
    }
    
    /// The encoder to use when serializing values.
    @inlinable
    public static var encoder: JSONEncoder {
        JSONEncoder()
    }
}
