//
//  Date+KeyValueStorable.swift
//  KeyValueKit
//
//  Created by Kyle Hughes on 2/25/24.
//

import Foundation

// MARK: - KeyValuePersistable Extension

extension Date: KeyValuePersistable, KeyValuePersistableAsProxy {
    // MARK: Public Typealiases
    
    public typealias Persistence = TimeInterval
}

// MARK: - KeyValueSerializable Extension

extension Date: KeyValueSerializable {
    // MARK: Public Typealiases
    
    public typealias Serialization = TimeInterval
    
    // MARK: Converting to and from KeyValueStorable Value
    
    @inlinable
    public static func deserialize(from serialization: @autoclosure () -> Serialization?) -> Self? {
        guard let serialization = serialization() else {
            return nil
        }
        
        return Date(timeIntervalSince1970: serialization)
    }
    
    @inlinable
    public func serialize() -> Serialization {
        timeIntervalSince1970
    }
}

// MARK: - KeyValueStorable Extension

extension Date: KeyValueStorable {}
