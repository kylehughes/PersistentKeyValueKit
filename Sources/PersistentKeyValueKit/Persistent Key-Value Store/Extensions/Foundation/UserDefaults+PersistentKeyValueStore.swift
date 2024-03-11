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
    
    /// Returns a dictionary that contains a union of all key-value pairs in the domains in the search list.
    ///
    /// - Returns: A dictionary containing the keys. The keys are names of defaults and the value corresponding to each 
    ///   key is a property list object (`NSData`, `NSString`, `NSNumber`, `NSDate`, `NSArray`, or `NSDictionary`).
    @inlinable
    public var dictionaryRepresentation: [String : Any] {
        dictionaryRepresentation()
    }
    
    #if DEBUG
    /// Gets the value for the given key.
    /// 
    /// The default value is returned if the key has not been set.
    ///
    /// In debug builds, this method will raise a fatal error if the key has not been registered before being retrieved,
    /// or configured otherwise. In production builds, registration is not checked.
    ///
    /// - Parameter key: The key to get the value for.
    /// - Returns: The value for the given key, or the default value if the key has not been set.
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
    /// Gets the value for the given key.
    ///
    /// The default value is returned if the key has not been set.
    ///
    /// - Parameter key: The key to get the value for.
    /// - Returns: The value for the given key, or the default value if the key has not been set.
    public func get<Key>(_ key: Key) -> Key.Value where Key: PersistentKeyProtocol {
        key.get(from: self)
    }
    #endif
    
    // MARK: Setting Values
    
    /// Sets the value for the given key.
    ///
    /// - Parameter key: The key to set the value for.
    /// - Parameter value: The new value for the key.
    @inlinable
    public func set<Key>(_ key: Key, to value: Key.Value) where Key: PersistentKeyProtocol {
        key.set(to: value, in: self)
    }
    
    // MARK: Removing Values
    
    /// Removes the value for the given key.
    ///
    /// - Parameter key: The key to remove the value for.
    @inlinable
    public func remove<Key>(_ key: Key) where Key: PersistentKeyProtocol {
        key.remove(from: self)
    }
    
    // MARK: Observing Keys
    
    /// Deregisters an observer for the given key.
    ///
    /// - Parameter target: The observer to deregister.
    /// - Parameter key: The key to stop observing.
    /// - Parameter context: The context to use for the observer.
    @inlinable
    public func deregister<Key>(
        observer target: NSObject,
        for key: Key,
        with context: UnsafeMutableRawPointer?
    ) where Key: PersistentKeyProtocol {
        removeObserver(target, forKeyPath: key.id, context: context)
    }
    
    /// Registers an observer for the given key.
    ///
    /// - Parameter target: The observer to register.
    /// - Parameter key: The key to observe.
    /// - Parameter context: The context to use for the observer.
    /// - Parameter valueWillChange: The closure to call when the value of the key changes.
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
    /// Registers the given keys with their default values.
    ///
    /// In debug builds, this method will record the registration of the keys for later checking. In production builds,
    /// registration is not recorded.
    ///
    /// - Parameter keys: The keys to register.
    public func register(_ keys: any PersistentKeyProtocol...) {
        var defaults: [String: Any] = [:]
        
        for key in keys {
            defaults[key.id] = key.defaultValue.serialize()
            RegistrationStorage.shared.didRegister(key.id, in: self)
        }
        
        register(defaults: defaults)
    }
    
    /// Registers the given keys with their default values.
    ///
    /// In debug builds, this method will record the registration of the keys for later checking. In production builds,
    /// registration is not recorded.
    ///
    /// - Parameter keys: The keys to register.
    public func register(_ keys: [any PersistentKeyProtocol]) {
        var defaults: [String: Any] = [:]
        
        for key in keys {
            defaults[key.id] = key.defaultValue.serialize()
            RegistrationStorage.shared.didRegister(key.id, in: self)
        }
        
        register(defaults: defaults)
    }
    #else

    /// Registers the given keys with their default values.
    ///
    /// - Parameter keys: The keys to register.
    @inlinable
    public func register(_ keys: any PersistentKeyProtocol...) {
        var defaults: [String: Any] = [:]
        
        for key in keys {
            defaults[key.id] = key.defaultValue.serialize()
        }
        
        register(defaults: defaults)
    }
    
    /// Registers the given keys with their default values.
    ///
    /// - Parameter keys: The keys to register.
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
