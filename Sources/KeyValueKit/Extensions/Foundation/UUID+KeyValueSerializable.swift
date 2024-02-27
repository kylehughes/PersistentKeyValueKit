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
    
    public typealias Serialization = String
    
    // MARK: Serializing & Deserializing
    
    @inlinable
    public static func deserialize(from serialization: @autoclosure () -> Serialization?) -> Self? {
        guard let serialization = serialization() else {
            return nil
        }
        
        return UUID(uuidString: serialization)
    }
    
    @inlinable
    public func serialize() -> Serialization {
        uuidString
    }
}
