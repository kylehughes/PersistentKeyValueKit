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
    public static func decode(from storage: @autoclosure () -> Serialization?) -> Self? {
        storage()
    }
    
    @inlinable
    public func encodeForStorage() -> Serialization {
        self
    }
}
