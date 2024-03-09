//
//  UserDefaultsStorage.swift
//  KeyValueKit
//
//  Created by Kyle Hughes on 3/21/21.
//

import Foundation

extension UserDefaults: PersistentKeyValueStore {
    // MARK: Getting Values
    
    @inlinable
    public var dictionaryRepresentation: [String : Any] {
        dictionaryRepresentation()
    }
    
    @inlinable
    public func get<Key>(_ key: Key) -> Key.Value where Key: PersistentKeyProtocol {
        key.get(from: self)
    }
    
    // MARK: Setting Values
    
    @inlinable
    public func set<Key>(_ key: Key, to value: Key.Value) where Key: PersistentKeyProtocol {
        key.set(to: value, in: self)
    }
    
    // MARK: Removing Values
    
    @inlinable
    public func remove<Key>(_ key: Key) where Key: PersistentKeyProtocol {
        key.remove(from: self)
    }
    
    // MARK: Observing Keys
    
    @inlinable
    public func deregister<Key>(
        observer target: NSObject,
        for key: Key,
        with context: UnsafeMutableRawPointer?
    ) where Key: PersistentKeyProtocol {
        removeObserver(target, forKeyPath: key.id, context: context)
    }
    
    @inlinable
    public func register<Key>(
        observer target: NSObject,
        for key: Key,
        with context: UnsafeMutableRawPointer?,
        valueWillChange: () -> Void
    ) where Key: PersistentKeyProtocol {
        addObserver(target, forKeyPath: key.id, context: context)
    }
}