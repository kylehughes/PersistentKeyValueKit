//
//  InMemoryPersistentKeyValueStore.swift
//  KeyValueKit
//
//  Created by Kyle Hughes on 3/23/21.
//

import Foundation

/// A key-value store that persists data in memory.
///
/// This store is useful for testing and development purposes.
public final class InMemoryPersistentKeyValueStore {
    private var storage: [String: Any]
    
    // MARK: Public Initialization
    
    /// Creates a new in-memory key-value store.
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
    
    /// Returns a dictionary that contains all key-value pairs.
    public var dictionaryRepresentation: [String : Any] {
        storage
    }
    
    /// Gets the value for the given key.
    ///
    /// The default value is returned if the key has not been set.
    ///
    /// - Parameter key: The key to get the value for.
    /// - Returns: The value for the given key, or the default value if the key has not been set.
    public func get<Key>(_ key: Key) -> Key.Value where Key: PersistentKeyProtocol {
        self[key.id] as? Key.Value ?? key.defaultValue
    }
    
    // MARK: Setting Values
    
    /// Sets the value for the given key.
    ///
    /// - Parameter key: The key to set the value for.
    /// - Parameter value: The new value for the key.
    public func set<Key>(_ key: Key, to value: Key.Value) where Key: PersistentKeyProtocol {
        self[key.id] = value
    }
    
    // MARK: Removing Values
    
    /// Removes the value for the given key.
    ///
    /// - Parameter key: The key to remove the value for.
    public func remove<Key>(_ key: Key) where Key: PersistentKeyProtocol {
        storage.removeValue(forKey: key.id)
    }
    
    // MARK: Observing Keys
    
    /// Deregisters an observer for the given key.
    ///
    /// - Parameter target: The observer to deregister.
    /// - Parameter key: The key to stop observing.
    /// - Parameter context: The context to use for the observer.
    public func deregister<Key>(
        observer target: NSObject,
        for key: Key,
        with context: UnsafeMutableRawPointer?
    ) where Key: PersistentKeyProtocol {
        fatalError("Unimplemented")
    }
    
    /// Registers an observer for the given key.
    ///
    /// - Parameter target: The observer to register.
    /// - Parameter key: The key to observe.
    /// - Parameter context: The context to use for the observer.
    /// - Parameter valueWillChange: The closure to call when the value of the key changes.
    public func register<Key>(
        observer target: NSObject,
        for key: Key,
        with context: UnsafeMutableRawPointer?,
        valueWillChange: () -> Void
    ) where Key: PersistentKeyProtocol {
        fatalError("Unimplemented")
    }
}
