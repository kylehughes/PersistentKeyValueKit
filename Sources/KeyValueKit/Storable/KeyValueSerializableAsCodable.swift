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
{}

// MARK: - KeyValueStorable Implementation

extension KeyValueSerializableAsCodable {
    // MARK: Converting to and from KeyValueStorable Value
    
    @inlinable
    public static func decode(from storage: @autoclosure () -> Serialization?) -> Self? {
        guard
            let jsonString = storage(),
            let json = jsonString.data(using: .utf8),
            let value = try? JSONDecoder().decode(Self.self, from: json)
        else {
            return nil
        }
        
        return value
    }
    
    @inlinable
    public func encodeForStorage() -> Serialization {
        String(data: try! JSONEncoder().encode(self), encoding: .utf8)!
    }
}
