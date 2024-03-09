//
//  InMemoryPersistentKeyValueStore.swift
//  KeyValueKit
//
//  Created by Kyle Hughes on 3/23/21.
//

import Foundation

public final class InMemoryPersistentKeyValueStore {
    private var storage: [String: Any]
    
    // MARK: Public Initialization
    
    public init() {
        storage = [:]
    }
    
    // MARK: Private Instance Interface
    
    private subscript(key: String) -> Any? {
        get {
            storage[key]
        }
        set {
            storage[key] = newValue
        }
    }
}

// MARK: - PersistentKeyValueStore Extension

extension InMemoryPersistentKeyValueStore: PersistentKeyValueStore {
    // MARK: Getting Values
    
    public var dictionaryRepresentation: [String : Any] {
        storage
    }
    
    public func get<Key>(_ key: Key) -> Key.Value where Key: PersistentKeyProtocol {
        self[key.id] as? Key.Value ?? key.defaultValue
    }
    
    // MARK: Setting Values
    
    public func set<Key>(_ key: Key, to value: Key.Value) where Key: PersistentKeyProtocol {
        self[key.id] = value
    }
    
    // MARK: Removing Values
    
    public func remove<Key>(_ key: Key) where Key: PersistentKeyProtocol {
        storage.removeValue(forKey: key.id)
    }
    
    // MARK: Observing Keys
    
    public func deregister<Key>(
        observer target: NSObject,
        for key: Key,
        with context: UnsafeMutableRawPointer?
    ) where Key: PersistentKeyProtocol {
        fatalError("Unimplemented")
    }
    
    public func register<Key>(
        observer target: NSObject,
        for key: Key,
        with context: UnsafeMutableRawPointer?,
        valueWillChange: () -> Void
    ) where Key: PersistentKeyProtocol {
        fatalError("Unimplemented")
    }
}
