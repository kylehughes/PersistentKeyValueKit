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
{}

// MARK: - KeyValueStorable Implementation

extension KeyValueSerializableAsRawRepresentable {
    // MARK: Converting to and from KeyValueStorable Value
    
    @inlinable
    public static func deserialize(from serialization: @autoclosure () -> Serialization?) -> Self? {
        guard let rawValue = RawValue.deserialize(from: serialization()), let value = Self(rawValue: rawValue) else {
            return nil
        }
        
        return value
    }
    
    @inlinable
    public func serialize() -> Serialization {
        rawValue.serialize()
    }
}
