//
//  PersistentKeyValueStore.swift
//  KeyValueKit
//
//  Created by Kyle Hughes on 3/21/21.
//

import Foundation

/// A protocol for a key-value store that persists data across app launches.
///
/// This interface is designed around the two persistent key-value stores provided by Apple platforms: `UserDefaults`
/// and `NSUbiquitousKeyValueStore`. It is not intended to support a generic key-value store implementation.
public protocol PersistentKeyValueStore {
    // MARK: Getting Values
    
    /// Returns a dictionary that contains all key-value pairs..
    var dictionaryRepresentation: [String: Any] { get }
    
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
    
    /// Deregisters an observer for the given key.
    ///
    /// - Parameter target: The observer to deregister.
    /// - Parameter key: The key to stop observing.
    /// - Parameter context: The context to use for the observer.
    func deregister<Key>(
        observer target: NSObject,
        for key: Key,
        with context: UnsafeMutableRawPointer?
    ) where Key: PersistentKeyProtocol
    
    /// Registers an observer for the given key.
    ///
    /// - Parameter target: The observer to register.
    /// - Parameter key: The key to observe.
    /// - Parameter context: The context to use for the observer.
    /// - Parameter valueWillChange: The closure to call when the value of the key changes.
    func register<Key>(
        observer target: NSObject,
        for key: Key,
        with context: UnsafeMutableRawPointer?,
        valueWillChange: @escaping () -> Void
    ) where Key: PersistentKeyProtocol
}

#if DEBUG

// MARK: - Preview

extension PersistentKeyValueStore where Self == InMemoryPersistentKeyValueStore {
    // MARK: Public Static Interface
    
    /// A store suitable for use in (e.g.) SwiftUI previews.
    @inlinable
    public static var preview: Self {
        InMemoryPersistentKeyValueStore()
    }
}

#endif
