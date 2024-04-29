//
//  KeyValuePersistible.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 4/13/24.
//

/// A type that can be a value in a ``PersistentKeyValueStore``.
public protocol KeyValuePersistible {
    // MARK: Associated Types
    
    /// The type of the representation of the key-value pair in the ``PersistentKeyValueStore``.
    associatedtype PersistentKeyValueRepresentation: PersistentKeyValueKit.PersistentKeyValueRepresentation<Self>
    
    // MARK: Static Interface
    
    /// The representation of the key-value pair in the ``PersistentKeyValueStore``.
    static var persistentKeyValueRepresentation: PersistentKeyValueRepresentation { get }
}
