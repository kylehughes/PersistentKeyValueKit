//
//  InMemoryKeyValueStore.swift
//  KeyValueKit
//
//  Created by Kyle Hughes on 3/23/21.
//

import Foundation

public final class InMemoryKeyValueStore {
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

// MARK: - KeyValueStore Extension

extension InMemoryKeyValueStore: KeyValueStore {
    // MARK: Getting Values
    
    public var dictionaryRepresentation: [String : Any] {
        storage
    }
    
    public func get<Key>(_ key: Key) -> Key.Value where Key: StorageKeyProtocol {
        self[key.id] as? Key.Value ?? key.defaultValue
    }
    
    // MARK: Setting Values
    
    public func set<Key>(_ key: Key, to value: Key.Value) where Key: StorageKeyProtocol {
        self[key.id] = value
    }
    
    // MARK: Removing Values
    
    public func remove<Key>(_ key: Key) where Key: StorageKeyProtocol {
        storage.removeValue(forKey: key.id)
    }
    
    // MARK: Observing Keys
    
    public func deregister<Key>(
        observer target: NSObject,
        for key: Key,
        with context: UnsafeMutableRawPointer?
    ) where Key: StorageKeyProtocol {
        fatalError("I should implement this.")
    }
    
    public func register<Key>(
        observer target: NSObject,
        for key: Key,
        with context: UnsafeMutableRawPointer?,
        valueWillChange: () -> Void
    ) where Key: StorageKeyProtocol {
        fatalError("I should implement this.")
    }
}
