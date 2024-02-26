//
//  UUID+Storable.swift
//  KeyValueKit
//
//  Created by Kyle Hughes on 2/25/24.
//

import Foundation

// MARK: - Storable Extension

extension UUID: Storable {
    // MARK: Public Typealiases
    
    public typealias StorableValue = String
    
    // MARK: Converting to and from Storable Value
    
    @inlinable
    public static func decode(from storage: @autoclosure () -> StorableValue?) -> Self? {
        guard let storableValue = storage() else {
            return nil
        }
        
        return UUID(uuidString: storableValue)
    }
    
    @inlinable
    public func encodeForStorage() -> StorableValue {
        uuidString
    }
}
