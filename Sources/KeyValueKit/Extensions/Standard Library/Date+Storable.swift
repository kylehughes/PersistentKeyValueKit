//
//  Date+Storable.swift
//  KeyValueKit
//
//  Created by Kyle Hughes on 2/25/24.
//

import Foundation

// MARK: - Storable Extension

extension Date: Storable {
    // MARK: Public Typealiases
    
    public typealias StorableValue = TimeInterval
    
    // MARK: Converting to and from Storable Value
    
    @inlinable
    public static func decode(from storage: @autoclosure () -> StorableValue?) -> Self? {
        guard let storableValue = storage() else {
            return nil
        }
        
        return Date(timeIntervalSince1970: storableValue)
    }
    
    @inlinable
    public func encodeForStorage() -> TimeInterval {
        timeIntervalSince1970
    }
}
