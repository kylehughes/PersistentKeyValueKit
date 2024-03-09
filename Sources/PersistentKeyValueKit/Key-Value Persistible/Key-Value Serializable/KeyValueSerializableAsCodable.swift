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
    
    static var decoder: JSONDecoder { get }
    static var encoder: JSONEncoder { get }
}

// MARK: - KeyValuePersistible Implementation

extension KeyValueSerializableAsCodable {
    // MARK: Converting to and from KeyValuePersistible Value
    
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
    
    @inlinable
    public static var decoder: JSONDecoder {
        JSONDecoder()
    }
    
    @inlinable
    public static var encoder: JSONEncoder {
        JSONEncoder()
    }
}
