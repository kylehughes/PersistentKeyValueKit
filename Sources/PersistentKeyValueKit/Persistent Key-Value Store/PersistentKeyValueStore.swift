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
///
/// ## Thread Safety
///
/// Conforming types are expected to be thread-safe. `UserDefaults` and `NSUbiquitousKeyValueStore` are documented by
/// Apple as thread-safe. This protocol is not marked `Sendable` because those classes are `open` and cannot be
/// retroactively conformed—subclasses could theoretically violate thread-safety. In practice, subclassing is
/// uncommon.
/// Implementations that are not thread-safe will exhibit undefined behavior or crash when used with observation APIs.
public protocol PersistentKeyValueStore {
    /// The migration capability for this store.
    ///
    /// Access throws when the backing store's writable persistent domain cannot be identified (such as a non-standard
    /// `UserDefaults` instance not created with `UserDefaults.migratable(suiteName:)` or `UserDefaults.standard`
    /// when `Bundle.main.bundleIdentifier` is unavailable).
    ///
    /// Custom store wrappers forward their backing store's endpoint (`try base.migrationEndpoint`). Forwarding
    /// delegates migration to the backing store directly without calling the wrapper's ``get(_:)``, ``set(_:to:)``,
    /// or ``remove(_:)`` methods.
    var migrationEndpoint: PersistentKeyValueMigrationEndpoint { get throws }

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
    /// Only the registration matching `observer`, `key`, and `context` is removed; the observer's registrations for
    /// other keys or contexts remain active. `UserDefaults` and `NSUbiquitousKeyValueStore` match key identifiers
    /// literally, as Foundation compares keys, so canonically equivalent spellings are different keys.
    ///
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
    /// If `Self` is `UserDefaults` then `target` is notified directly through
    /// `observeValue(forKeyPath:of:change:context:)` with the key's identifier as the key path. Key-value observation
    /// parses an identifier as a key path, so it is used only for identifiers that it reads as one key. It does not
    /// report a write of a value that Foundation considers equal to the stored value, such as an `Int64` over an equal
    /// `Int32` or `-0.0` over `0.0`, so `target` is not notified of such a write. An identifier that is empty, begins
    /// with `@`, contains a period (`.`) code unit (even inside a combined character) or NUL, or is `valueForKey:` or
    /// `ValueForKey:` is observed through `UserDefaults.didChangeNotification` instead. After
    /// each such notification, the key is read from this instance, and `target` is notified when the property-list
    /// value read differs from the previous read (or once on the next reconciliation pass if the registration joined
    /// while a reconciliation was in progress and any change was reported since it joined, even when the value read
    /// equals its comparison value). Changes are sampled rather than queued, so rapid writes between reads can
    /// coalesce and a change that is undone before it is sampled can produce no notification. Foundation posts that
    /// notification only for changes made in the current process, and not for `addSuite(named:)` or
    /// `removeSuite(named:)`, so changes to such a key made by another process, or caused only by a suite-list change,
    /// might not be delivered. For these keys `target` can be notified on a thread other than the one that made the
    /// change, while that thread delivers concurrent changes.
    ///
    /// If `Self` is `NSUbiquitousKeyValueStore` then notifications will be used and `target` will be notified through
    /// the `selector` with the store's change notification. `target` is notified when the notification lists `key`, and
    /// when it might have changed every key: an account change, or a notification without a list of changed keys.
    ///
    /// Neither the object receiving this message, nor observer, are retained. An object that calls this method must
    /// also eventually call ``deregister(_:for:context:)`` to unregister the observer.
    ///
    /// - Parameter observer: The observer to register.
    /// - Parameter key: The key to observe.
    /// - Parameter context: Arbitrary data that identifies the registration to ``deregister(_:for:context:)`` and is
    ///   passed to `observeValue(forKeyPath:of:change:context:)` for `UserDefaults` and
    ///   ``InMemoryPersistentKeyValueStore``.
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
