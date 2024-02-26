//
//  StorableAsSelf.swift
//  KeyValueKit
//
//  Created by Kyle Hughes on 2/25/24.
//

import Foundation

public protocol StorableAsSelf: Storable 
where
    StorableValue == Self
{}

// MARK: - Storable Extension

extension StorableAsSelf {
    // MARK: Converting to and from Storable Value
    
    @inlinable
    public static func decode(from storage: @autoclosure () -> StorableValue?) -> Self? {
        storage()
    }
    
    @inlinable
    public func encodeForStorage() -> StorableValue {
        self
    }
}
