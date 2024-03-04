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
{}

// MARK: - KeyValueSerializable Extension

extension KeyValueSerializableAsSelf {
    // MARK: Serializing & Deserializing
    
    @inlinable
    public static func deserialize(from serialization: @autoclosure () -> Serialization?) -> Self? {
        serialization()
    }
    
    @inlinable
    public func serialize() -> Serialization {
        self
    }
}
