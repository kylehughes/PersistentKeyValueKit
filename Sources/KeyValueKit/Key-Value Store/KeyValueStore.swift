//
//  KeyValueStore.swift
//  KeyValueKit
//
//  Created by Kyle Hughes on 3/21/21.
//

import Foundation

public protocol KeyValueStore {
    // MARK: Getting Values
    
    var dictionaryRepresentation: [String: Any] { get }
    
    func get<Key>(_ key: Key) -> Key.Value where Key: StoreKeyProtocol
    
    // MARK: Setting Values
    
    func set<Key>(_ key: Key, to value: Key.Value) where Key: StoreKeyProtocol
    
    // MARK: Removing Values
    
    func remove<Key>(_ key: Key) where Key: StoreKeyProtocol
    
    // MARK: Observing Keys
    
    func deregister<Key>(
        observer target: NSObject,
        for key: Key,
        with context: UnsafeMutableRawPointer?
    ) where Key: StoreKeyProtocol
    
    func register<Key>(
        observer target: NSObject,
        for key: Key,
        with context: UnsafeMutableRawPointer?,
        valueWillChange: @escaping () -> Void
    ) where Key: StoreKeyProtocol
}

#if DEBUG
// MARK: - Preview

extension KeyValueStore where Self == InMemoryKeyValueStore {
    // MARK: Public Static Interface
    
    @inlinable
    public static var preview: Self {
        InMemoryKeyValueStore()
    }
}
#endif
