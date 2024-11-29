//
//  PersistentKeyValueStore.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 3/21/21.
//

import Foundation

/// A protocol for a key-value store that persists data across app launches.
///
/// This interface is molded to the two persistent key-value stores provided by Apple platforms: `UserDefaults` and 
/// `NSUbiquitousKeyValueStore`. It takes necessary liberties by being fully aware of these implementations. It is not
/// intended to support a generic key-value store implementation.
public protocol PersistentKeyValueStore {
    // MARK: Getting Values
    
    /// Gets the value for the given key.
    ///
    /// The default value is returned if the key has not been set.
    ///
    /// - Parameter key: The key to get the value for.
    /// - Returns: The value for the given key, or the default value if the key has not been set.
    func get<Key>(_ key: Key) -> Key.Value where Key: PersistentKeyProtocol
    
    // MARK: Setting Values
    
    /// Sets the value for the given key.
    ///
    /// - Parameter key: The key to set the value for.
    /// - Parameter value: The new value for the key.
    func set<Key>(_ key: Key, to value: Key.Value) where Key: PersistentKeyProtocol
    
    // MARK: Removing Values
    
    /// Removes the value for the given key.
    ///
    /// - Parameter key: The key to remove the value for.
    func remove<Key>(_ key: Key) where Key: PersistentKeyProtocol
    
    // MARK: Observing Keys
    
    /// Removes an observer for the given key.
    ///
    /// - Important: This is a `NO-OP`, and not a concern, for `NSUbiquitousKeyValueStore`.
    /// - Parameter observer: The object to remove as an observer.
    /// - Parameter key: The key to stop observing.
    /// - Parameter context: Arbitrary data that more specifically identifies the observer to be removed.
    func deregister<Key>(
        _ observer: NSObject,
        for key: Key,
        context: UnsafeMutableRawPointer?
    ) where Key: PersistentKeyProtocol
    
    /// Registers an observer for the given key.
    ///
    /// This is used to orchestrate the SwiftUI property wrapper. This is not intended to provide a general way to
    /// observe changes to keys: its ergonomics are specifically designed for implementing
    /// ``PersistentKeyUIObservableObject``, knowing that the implementation is either `UserDefaults` or
    /// `NSUbiquitousKeyValueStore`.
    ///
    /// If `Self` is `UserDefaults` then key-value observation, notifying `target` directly, will be used. If `Self` is
    /// `NSUbiquitousKeyValueStore` then notifications will be used and `target` will be notified through the
    /// `selector`.
    ///
    /// For `UserDefaults`, neither the object receiving this message, nor observer, are retained. An object that calls
    /// this method must also eventually call either the ``deregister(_:forKeyPath:context:)`` method to unregister the
    /// observer.
    ///
    /// - Parameter observer: The observer to register.
    /// - Parameter key: The key to observe.
    /// - Parameter context: The context to use for `UserDefaults` key-value observation. This is a `NO-OP` for
    ///   `NSUbiquitousKeyValueStore`.
    /// - Parameter selector: The selector to use for `NSUbiquitousKeyValueStore` notification observation. This is a
    ///   `NO-OP` for `UserDefaults`.
    func register<Key>(
        observer: NSObject,
        for key: Key,
        with context: UnsafeMutableRawPointer?,
        and selector: Selector
    ) where Key: PersistentKeyProtocol
}

// MARK: Bespoke Implementation

extension PersistentKeyValueStore {
    // MARK: Public Subscripts

    /// Gets the value for the given key.
    ///
    /// The default value is returned if the key has not been set.
    ///
    /// - Parameter key: The key to get the value for.
    /// - Returns: The value for the given key, or the default value if the key has not been set.
    @inlinable
    public subscript<Value>(_ key: some PersistentKeyProtocol<Value>) -> Value {
        self.get(key)
    }
}
