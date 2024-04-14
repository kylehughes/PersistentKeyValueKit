//
//  KeyValuePersistible.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 4/13/24.
//

public protocol NewKeyValuePersistible {
    // MARK: Associated Types
    
    associatedtype PersistentKeyValueRepresentation: PersistentKeyValueKit.PersistentKeyValueRepresentation<Self>
    
    // MARK: Static Interface
    
    static var persistentKeyValueRepresentation: PersistentKeyValueRepresentation { get }
}
