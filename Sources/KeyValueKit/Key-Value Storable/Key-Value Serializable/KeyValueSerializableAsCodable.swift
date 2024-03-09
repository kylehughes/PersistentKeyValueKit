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
    // NO-OP
}

// MARK: - KeyValuePersistible Implementation

extension KeyValueSerializableAsCodable {
    // MARK: Converting to and from KeyValuePersistible Value
    
    @inlinable
    public static func deserialize(from serialization: @autoclosure () -> Serialization?) -> Self? {
        guard
            let jsonString = serialization(),
            let json = jsonString.data(using: .utf8),
            let value = try? JSONDecoder().decode(Self.self, from: json)
        else {
            return nil
        }
        
        return value
    }
    
    @inlinable
    public func serialize() -> Serialization {
        String(data: try! JSONEncoder().encode(self), encoding: .utf8)!
    }
}
