//
//  PersistentKeyValueStore.swift
//  KeyValueKit
//
//  Created by Kyle Hughes on 3/21/21.
//

import Foundation

public protocol PersistentKeyValueStore {
    // MARK: Getting Values
    
    var dictionaryRepresentation: [String: Any] { get }
    
    func get<Key>(_ key: Key) -> Key.Value where Key: PersistentKeyProtocol
    
    // MARK: Setting Values
    
    func set<Key>(_ key: Key, to value: Key.Value) where Key: PersistentKeyProtocol
    
    // MARK: Removing Values
    
    func remove<Key>(_ key: Key) where Key: PersistentKeyProtocol
    
    // MARK: Observing Keys
    
    func deregister<Key>(
        observer target: NSObject,
        for key: Key,
        with context: UnsafeMutableRawPointer?
    ) where Key: PersistentKeyProtocol
    
    func register<Key>(
        observer target: NSObject,
        for key: Key,
        with context: UnsafeMutableRawPointer?,
        valueWillChange: @escaping () -> Void
    ) where Key: PersistentKeyProtocol
}

#if DEBUG
// MARK: - Preview

extension PersistentKeyValueStore where Self == InMemoryPersistentKeyValueStore {
    // MARK: Public Static Interface
    
    @inlinable
    public static var preview: Self {
        InMemoryPersistentKeyValueStore()
    }
}
#endif
