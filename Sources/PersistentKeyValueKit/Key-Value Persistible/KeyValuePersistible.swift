//
//  KeyValuePersistible.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 4/13/24.
//

/// A type whose values can be persisted in a ``PersistentKeyValueStore``.
///
/// Conforming types supply ``persistentKeyValueRepresentation`` to convert values to and from a store's underlying
/// storage format.
public protocol KeyValuePersistible {
    // MARK: Associated Types
    
    /// The representation type that converts `Self` to and from storage objects in a ``PersistentKeyValueStore``.
    associatedtype PersistentKeyValueRepresentation: PersistentKeyValueKit.PersistentKeyValueRepresentation<Self>
    
    // MARK: Static Interface
    
    /// The representation used by default when persisting `Self` in a ``PersistentKeyValueStore``.
    static var persistentKeyValueRepresentation: Self.PersistentKeyValueRepresentation { get }
}
