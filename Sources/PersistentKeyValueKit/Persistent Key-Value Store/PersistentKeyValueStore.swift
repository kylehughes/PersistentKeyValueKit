//
//  PersistentKeyValueStore.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 3/21/21.
//

import Foundation

/// A typed interface for reading, writing, and observing key-value pairs. The backing store determines their lifetime.
///
/// This interface is molded to the two persistent key-value stores provided by Apple platforms: `UserDefaults` and
/// `NSUbiquitousKeyValueStore`. It takes necessary liberties by being fully aware of these implementations. It is not
/// intended to support a generic key-value store implementation.
///
/// Use any of the built-in stores through the same typed keys: `UserDefaults.standard`, a `UserDefaults` suite,
/// `NSUbiquitousKeyValueStore.default`, or ``InMemoryPersistentKeyValueStore``. Using
/// `NSUbiquitousKeyValueStore.default`, including for local reads and writes, requires the iCloud capability with
/// Key-value storage selected on each app target that uses it; without the entitlement, a typed read can return the
/// key's default after a typed write.
///
/// ## Thread Safety
///
/// Conforming types are expected to be thread-safe. `UserDefaults` and `NSUbiquitousKeyValueStore` are documented by
/// Apple as thread-safe. This protocol is not marked `Sendable`. A retroactive `@unchecked Sendable` conformance on
/// either open Foundation class would also vouch for the thread safety of its subclasses. In practice, subclassing is
/// uncommon.
/// Implementations that are not thread-safe will exhibit undefined behavior or crash when used with observation APIs.
public protocol PersistentKeyValueStore {
    // MARK: Migrating Values

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
    /// A `UserDefaults` store removes the value from its persistent domain only, so later reads return the key's default
    /// value unless another domain, such as launch arguments or registered defaults, supplies a value.
    ///
    /// - Parameter key: The key to remove the value for.
    func remove<Key>(_ key: Key) where Key: PersistentKeyProtocol
    
    // MARK: Observing Keys
    
    /// Removes an observer for the given key.
    ///
    /// Only registrations matching `observer`, `key`, and `context` are removed; the observer's registrations for
    /// other keys or contexts remain active. A store that keeps its own registrations, such as
    /// `NSUbiquitousKeyValueStore`, removes every matching registration in one call, whereas a `UserDefaults` key
    /// observed through key-value observation removes one per call. `UserDefaults` and `NSUbiquitousKeyValueStore` match
    /// key identifiers literally, as Foundation compares keys, so canonically equivalent spellings are different keys.
    /// ``InMemoryPersistentKeyValueStore`` matches identifiers as Swift strings, so one call removes every matching
    /// registration.
    ///
    /// Deregister before releasing a manual observer. A `UserDefaults` key observed through
    /// `UserDefaults.didChangeNotification` continues to be sampled until its registration is removed or pruned, even
    /// after its observer deallocates. A repeated removal for a key that key-value observation can observe raises an
    /// exception, so cleanup after a callback must account for it. Deregistration prevents later callbacks from
    /// starting delivery, but a callback already in flight can still reach the observer. When several threads
    /// deregister the same notification-backed observation concurrently, only the call that removes the registrations
    /// invalidates them, so wait for that call to finish before relying on the observer being quiet: another call can
    /// return first, and a notification posted in that window can still reach the observer.
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
    /// `observeValue(forKeyPath:of:change:context:)` with the key's identifier as the key path, only for the
    /// registered key. Key-value observation
    /// parses an identifier as a key path, so it is used only for identifiers that it reads as one key. It does not
    /// report a write of a value that Foundation considers equal to the stored value, such as an `Int64` over an equal
    /// `Int32` or `-0.0` over `0.0`, so `target` is not notified of such a write. An identifier that is empty, begins
    /// with `@`, contains a period (`.`) code unit (even inside a combined character) or NUL, or is `valueForKey:` or
    /// `ValueForKey:` is observed through `UserDefaults.didChangeNotification` instead. After
    /// each such notification, the key is read from this instance, and `target` is notified when the property-list
    /// value read differs from the previous read (or, for a registration inserted while a reconciliation was in
    /// progress, also once if the change count advanced between the start of its initial read and the start of the
    /// first pass that includes it, even when the value read equals its comparison value). The comparison reads the
    /// effective value and compares the widths of the integers it reads. Several notifications can share one read of
    /// the key. Changes are sampled rather than queued, so rapid writes between reads can
    /// coalesce and a change that is undone before it is sampled can produce no notification. Foundation posts that
    /// notification only for changes made in the current process, and not for `addSuite(named:)` or
    /// `removeSuite(named:)`, so changes to such a key made by another process, or caused only by a suite-list change,
    /// might not be delivered. For these keys `target` can be notified on a thread other than the one that made the
    /// change, while that thread delivers concurrent changes.
    ///
    /// If `Self` is `NSUbiquitousKeyValueStore` then notifications will be used and `target` will be notified through
    /// the `selector` with the store's change notification, and only for notifications that concern its registered
    /// literal key. Each matching registration receives the full notification, including keys the registration did not
    /// ask for. `target` is notified when the
    /// notification lists `key`, and when it might have changed every key: an account change, or a missing or unusable
    /// list of changed keys. A usable empty list matches no key.
    ///
    /// If `Self` is ``InMemoryPersistentKeyValueStore`` then `target` is called synchronously on the writing thread
    /// through `observeValue(forKeyPath:of:change:context:)` with the identifier that the write or removal received as
    /// the key path, `nil` for `change`, and the registered context, even when removing an absent key.
    ///
    /// Neither the object receiving this message, nor observer, are retained. An object that calls this method must
    /// also eventually call ``deregister(_:for:context:)`` to unregister the observer. A callback delivered during
    /// registration can deregister itself. Keep a custom key's ``PersistentKeyProtocol/id`` unchanged from
    /// registration through deregistration, because a changed `id` can remove a path that was never registered, which
    /// raises an exception. Remove each key-value observation registration once, using the same store, observer, key,
    /// and context.
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
