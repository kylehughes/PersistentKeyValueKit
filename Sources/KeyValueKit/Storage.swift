//
//  Storage.swift
//  KeyValueKit
//
//  Created by Kyle Hughes on 3/21/21.
//

import Foundation

public protocol Storage {
    // MARK: Getting Values
    
    var dictionaryRepresentation: [String: Any] { get }
    
    func get<Key>(_ key: Key) -> Key.Value where Key: StorageKeyProtocol
    
    // MARK: Setting Values
    
    func set<Key>(_ key: Key, to value: Key.Value) where Key: StorageKeyProtocol
    
    // MARK: Removing Values
    
    func remove<Key>(_ key: Key) where Key: StorageKeyProtocol
    
    // MARK: Observing Keys
    
    func deregister<Key>(
        observer target: NSObject,
        for key: Key,
        with context: UnsafeMutableRawPointer?
    ) where Key: StorageKeyProtocol
    
    func register<Key>(
        observer target: NSObject,
        for key: Key,
        with context: UnsafeMutableRawPointer?,
        valueWillChange: @escaping () -> Void
    ) where Key: StorageKeyProtocol
}

#if DEBUG
// MARK: - Preview

extension Storage where Self == InMemoryStorage {
    // MARK: Public Static Interface
    
    public static var preview: Self {
        InMemoryStorage()
    }
}
#endif
