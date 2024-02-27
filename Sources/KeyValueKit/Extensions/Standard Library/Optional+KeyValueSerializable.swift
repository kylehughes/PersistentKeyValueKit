//
//  Optional+KeyValueSerializable.swift
//  KeyValueKit
//
//  Created by Kyle Hughes on 2/27/24.
//

import Foundation

// MARK: - KeyValueSerializable Extension

extension Optional: KeyValueSerializable where Wrapped: KeyValueSerializable {
    // MARK: Public Typealiases
    
    public typealias Serialization = Wrapped.Serialization?
    
    // MARK: Serialization & Deserialization
    
    @inlinable
    public static func deserialize(from serialization: @autoclosure () -> Serialization?) -> Self? {
        guard
            let wrappedSerialization = serialization(),
            let unwrappedSerialization = wrappedSerialization
        else {
            return nil
        }
        
        return Wrapped.deserialize(from: unwrappedSerialization)
    }
    
    @inlinable
    public func serialize() -> Serialization {
        switch self {
        case .none:
            return nil
        case let .some(wrapped):
            return wrapped.serialize()
        }
    }
}
