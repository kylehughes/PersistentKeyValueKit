//
//  UserDefaults+PersistentKeyValueStore.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 3/21/21.
//

import Foundation

// MARK: - PersistentKeyValueStore Extension

extension UserDefaults: PersistentKeyValueStore {
    // MARK: Getting Values
    
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
        _ observer: NSObject,
        for key: Key,
        context: UnsafeMutableRawPointer?
    ) where Key : PersistentKeyProtocol {
        removeObserver(observer, forKeyPath: key.id, context: context)
    }
    
    @inlinable
    public func register<Key>(
        observer target: NSObject,
        for key: Key,
        with context: UnsafeMutableRawPointer?,
        and selector: Selector
    ) where Key: PersistentKeyProtocol {
        addObserver(target, forKeyPath: key.id, context: context)
    }
}

// MARK: - Bespoke Implementation

extension UserDefaults {
    // MARK: Register Default Values

    /// Registers the given keys with their default values.
    ///
    /// - Parameter keys: The keys to register.
    @inlinable
    public func register(_ keys: any PersistentKeyProtocol...) {
       register(keys)
    }
    
    /// Registers the given keys with their default values.
    ///
    /// - Parameter keys: The keys to register.
    public func register(_ keys: [any PersistentKeyProtocol]) {
        var defaults: [String: Any] = Dictionary(minimumCapacity: keys.capacity)
        
        for key in keys {
            key.registerDefault(in: &defaults)
        }
        
        register(defaults: defaults)
    }
}

// MARK: - Static Accessors

extension PersistentKeyValueStore where Self == UserDefaults {
    // MARK: Public Static Interface
    
    /// A convenient way to access `UserDefaults.standard`.
    ///
    /// If you construct your own `UserDefaults` for an app group, we encourage you to make your own static accessor
    /// for your convenience.
    @inlinable
    public static var local: Self {
        .standard
    }
}
