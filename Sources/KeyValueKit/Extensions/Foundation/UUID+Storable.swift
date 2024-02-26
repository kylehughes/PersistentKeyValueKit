//
//  UUID+KeyValueStorable.swift
//  KeyValueKit
//
//  Created by Kyle Hughes on 2/25/24.
//

import Foundation

// MARK: - KeyValuePersistable Extension

extension UUID: KeyValuePersistable, KeyValuePersistableAsProxy {
    // MARK: Public Typealiases
    
    public typealias Persistence = String
}

// MARK: - KeyValueSerializable Extension

extension UUID: KeyValueSerializable {
    // MARK: Public Typealiases
    
    public typealias Serialization = String
    
    // MARK: Serializing & Deserializing
    
    @inlinable
    public static func decode(from storage: @autoclosure () -> Serialization?) -> Self? {
        guard let serialization = storage() else {
            return nil
        }
        
        return UUID(uuidString: serialization)
    }
    
    @inlinable
    public func encodeForStorage() -> Serialization {
        uuidString
    }
}

// MARK: - KeyValueStorable Extension

extension UUID: KeyValueStorable {}
