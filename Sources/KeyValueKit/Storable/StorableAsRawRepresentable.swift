//
//  StorableAsRawRepresentable.swift
//  KeyValueKit
//
//  Created by Kyle Hughes on 2/25/24.
//

import Foundation

public protocol StorableAsRawRepresentable: Storable, RawRepresentable
where
    RawValue: Storable,
    StorableValue == RawValue,
    StorableValue == RawValue.StorableValue
{}

// MARK: - Storable Implementation

extension StorableAsRawRepresentable {
    // MARK: Converting to and from Storable Value
    
    @inlinable
    public static func decode(from storage: @autoclosure () -> StorableValue?) -> Self? {
        guard let rawValue = RawValue.decode(from: storage()), let value = Self(rawValue: rawValue) else {
            return nil
        }
        
        return value
    }
    
    @inlinable
    public func encodeForStorage() -> StorableValue {
        rawValue.encodeForStorage()
    }
}
