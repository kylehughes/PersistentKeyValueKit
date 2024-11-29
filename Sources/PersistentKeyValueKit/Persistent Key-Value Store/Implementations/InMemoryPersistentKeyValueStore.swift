//
//  InMemoryPersistentKeyValueStore.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 3/23/21.
//

import Foundation

/// A key-value store that persists data in memory.
///
/// This store is useful for testing and development purposes, although `UserDefaults.standard` often works just as
/// well.
///
/// There is nothing that prevents it from being used in production, but it may be a sign that you are using the library 
/// unnecessarily. The library is intended to be used exclusively as a general interface on top of the two persistent
/// key-value stores provided by Apple platforms: `UserDefaults` and `NSUbiquitousKeyValueStore`.
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
    
    public func get<Key>(_ key: Key) -> Key.Value where Key: PersistentKeyProtocol {
        self[key.id] as? Key.Value ?? key.defaultValue
    }
    
    // MARK: Setting Values
    
    public func set<Key>(_ key: Key, to value: Key.Value) where Key: PersistentKeyProtocol {
        // We loosely try to replicate property list behavior of not representing `nil` values in storage.
        if let array = value as? [Any?] {
            self[key.id] = array.compactMap(\.self)
        } else if let dict = value as? [String: Any?] {
            self[key.id] = dict.compactMapValues(\.self)
        } else {
            self[key.id] = value
        }
    }
    
    // MARK: Removing Values
    
    public func remove<Key>(_ key: Key) where Key: PersistentKeyProtocol {
        storage.removeValue(forKey: key.id)
    }
    
    // MARK: Observing Keys
    
    @inlinable
    public func deregister<Key>(
        _ observer: NSObject,
        for key: Key,
        context: UnsafeMutableRawPointer?
    ) where Key : PersistentKeyProtocol {
        // NO-OP
    }
    
    public func register<Key>(
        observer target: NSObject,
        for key: Key,
        with context: UnsafeMutableRawPointer?,
        and selector: Selector
    ) where Key: PersistentKeyProtocol {
        // NO-OP
    }
}

// MARK: - Static Accessors

extension PersistentKeyValueStore where Self == InMemoryPersistentKeyValueStore {
    // MARK: Public Static Interface
    
    /// A store suitable for use in development, e.g. SwiftUI previews.
    @inlinable
    public static var ephemeral: Self {
        InMemoryPersistentKeyValueStore()
    }
}
