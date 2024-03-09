//
//  UserDefaultsStorage.swift
//  KeyValueKit
//
//  Created by Kyle Hughes on 3/21/21.
//

import Foundation

// MARK: - PersistentKeyValueStore Extension

extension UserDefaults: PersistentKeyValueStore {
    // MARK: Getting Values
    
    @inlinable
    public var dictionaryRepresentation: [String : Any] {
        dictionaryRepresentation()
    }
    
    #if DEBUG
    public func get<Key>(_ key: Key) -> Key.Value where Key: PersistentKeyProtocol {
        guard
            PersistentKeyValueKitConfiguration.shouldSkipRegistrationCheckInDebug ||
            RegistrationStorage.shared.is(key, registeredIn: self)
        else {
            fatalError("Key \(key.id) must be registered before being retrieved.")
        }
        
        return key.get(from: self)
    }
    #else
    @inlinable
    public func get<Key>(_ key: Key) -> Key.Value where Key: PersistentKeyProtocol {
        key.get(from: self)
    }
    #endif
    
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

// MARK: - Bespoke Implementation

extension UserDefaults {
    // MARK: Register Default Values
    
    #if DEBUG
    public func register(_ keys: [any PersistentKeyProtocol]) {
        var defaults: [String: Any] = [:]
        
        for key in keys {
            defaults[key.id] = key.defaultValue.serialize()
            RegistrationStorage.shared.didRegister(key.id, in: self)
        }
        
        register(defaults: defaults)
    }
    #else
    @inlinable
    public func register(_ keys: [any PersistentKeyProtocol]) {
        var defaults: [String: Any] = [:]
        
        for key in keys {
            defaults[key.id] = key.defaultValue.serialize()
        }
        
        register(defaults: defaults)
    }
    #endif
}

#if DEBUG

// MARK: - RegistrationStorage Definition

private class RegistrationStorage {
    fileprivate static let shared = RegistrationStorage()
    
    private let lock: NSRecursiveLock
    
    private var storage: [ObjectIdentifier: Set<String>]
    
    // MARK: Fileprivate Initialization
    
    fileprivate init() {
        lock = NSRecursiveLock()
        storage = [:]
    }
    
    // MARK: Fileprivate Instance Interface
    
    fileprivate func didRegister(_ id: String, in userDefaults: UserDefaults) {
        lock.lock()
        
        defer {
            lock.unlock()
        }
        
        let key = ObjectIdentifier(userDefaults)

        storage[key] = {
            var registeredIDs = storage[key, default: []]
            registeredIDs.insert(id)
            return registeredIDs
        }()
    }
    
    fileprivate func `is`(_ key: some PersistentKeyProtocol, registeredIn userDefaults: UserDefaults) -> Bool {
        lock.lock()
        
        defer {
            lock.unlock()
        }
        
        guard let registeredIDs = storage[ObjectIdentifier(userDefaults)] else {
            return false
        }
        
        return registeredIDs.contains(key.id)
    }
}

#endif
