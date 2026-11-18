//
//  PersistentKeyUIObservableObject.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 6/13/22.
//

import Combine
import Foundation

/// A `MainActor`-isolated observer for a key in a ``PersistentKeyValueStore``.
///
/// `PersistentKeyUIObservableObject` drives ``PersistentValue`` by registering with any ``PersistentKeyValueStore``
/// through ``PersistentKeyValueStore/register(observer:for:with:and:)`` and
/// ``PersistentKeyValueStore/deregister(_:for:context:)`` (for example, KVO on `UserDefaults`, `NotificationCenter` on
/// `NSUbiquitousKeyValueStore`, and direct callbacks on ``InMemoryPersistentKeyValueStore``).
///
/// - Important: Using this class with `NSUbiquitousKeyValueStore` requires local (in-app) mutations to be performed
///   through ``PersistentKeyValueStore``, ``PersistentValue``, or store migration. Foundation posts
///   `NSUbiquitousKeyValueStore.didChangeExternallyNotification` only for changes received from iCloud, so
///   `PersistentKeyValueKit` posts `NSUbiquitousKeyValueStore.didChangeInternallyNotification` for local writes and
///   removals.
/// - Note: For `UserDefaults` keys whose identifiers are empty, begin with `@`, contain a period (`.`) code unit
///   (even inside a combined character) or NUL, or are `valueForKey:` or `ValueForKey:`, only changes made in the
///   current process are observed. Changes made by another process, such as an app extension that shares an app group,
///   might not be delivered, and neither are changes caused only by `addSuite(named:)` or `removeSuite(named:)`.
@MainActor
public final class PersistentKeyUIObservableObject<Key>: ObservableObject where Key: PersistentKeyProtocol {
    /// The key being observed.
    ///
    /// ``PersistentValue`` replaces the key when its view is updated with a different key.
    public private(set) var key: Key

    /// The store that the key is being observed in.
    private var _store: (any PersistentKeyValueStore)?

    /// The registration lifetime for the current store.
    private var observation: StoreObservation<Key>?

    /// The number of registrations started, which tells a registration whether it is still current when it returns.
    private var registrationCount: Int
    
    // MARK: Public Initialization
    
    /// Creates a new observer for the given key in the given store.
    ///
    /// - Parameter store: The store to observe the key in.
    /// - Parameter key: The key to observe.
    public init(store: (any PersistentKeyValueStore)?, key: Key) {
        self.key = key
        
        _store = store
        registrationCount = 0

        registerObserver(on: store)
    }
    
    // MARK: Public Instance Interface
    
    /// The store that the key is being observed in.
    ///
    /// Setting the store observes the new store. If a subscriber to `objectWillChange` sets the store again while the
    /// new store is being registered, the latest store is observed and the earlier registration is removed.
    public var store: (any PersistentKeyValueStore)? {
        get {
            _store
        }
        set {
            observation = nil
            
            _store = newValue
            
            registerObserver(on: newValue)
        }
    }
    
    /// The value of the key in the store.
    ///
    /// Setting the value writes to the key and store that are current when the setter is called, even if a subscriber
    /// to `objectWillChange` replaces the store before the write.
    public var value: Key.Value {
        get {
            Self.value(for: key, in: _store)
        }
        set {
            let key = key
            let store = _store

            objectWillChange.send()

            Self.setValue(newValue, for: key, in: store)
        }
    }

    // MARK: Internal Static Interface

    /// Returns the value of `key` in `store`, or the key's default value when there is no store.
    internal static func value(for key: Key, in store: (any PersistentKeyValueStore)?) -> Key.Value {
        assertStoreExists(store)

        return store?.get(key) ?? key.defaultValue
    }

    /// Writes `newValue` for `key` in `store`.
    ///
    /// The caller captures `key` and `store` before notifying subscribers that the object will change, so a subscriber
    /// that replaces the observed key or store cannot redirect the write.
    internal static func setValue(_ newValue: Key.Value, for key: Key, in store: (any PersistentKeyValueStore)?) {
        assertStoreExists(store)

        store?.set(key, to: newValue)
    }

    // MARK: Internal Instance Interface

    /// Observes `key` in `store`, replacing the current observation when the key identifier or store changes.
    ///
    /// The latest key is always adopted so reads use its current default value and representation. The observation is
    /// replaced only when the key identifier or the store instance differs, so repeated view updates with the same
    /// inputs keep the existing registration. Key identifiers are compared literally, as Foundation stores compare
    /// keys, so a change between canonically equivalent spellings observes the new key.
    internal func update(key newKey: Key, store newStore: any PersistentKeyValueStore) {
        let keyIDChanged = !StoreKeyObservationRegistry.keyIDsMatch(newKey.id, key.id)

        key = newKey

        guard keyIDChanged || !Self.isSameStore(_store, newStore) else {
            return
        }

        store = newStore
    }

    // MARK: Private Static Interface

    private static func assertStoreExists(_ store: (any PersistentKeyValueStore)?) {
        assert(store != nil, "Store should always be set on initialization or immediately after.")
    }

    /// Returns whether two stores are the same instance.
    ///
    /// Value-type stores have no identity, so they are never considered the same and are observed again on every
    /// update.
    private static func isSameStore(
        _ lhs: (any PersistentKeyValueStore)?,
        _ rhs: any PersistentKeyValueStore
    ) -> Bool {
        guard let lhs, type(of: lhs) is AnyClass, type(of: rhs) is AnyClass else {
            return false
        }

        return (lhs as AnyObject) === (rhs as AnyObject)
    }

    // MARK: Private Instance Interface

    private func registerObserver(on store: (any PersistentKeyValueStore)?) {
        registrationCount &+= 1

        guard let store else {
            return
        }

        let registration = registrationCount

        // The observer filters callbacks by key identifier, so each registration creates one for the current key.
        let observer = Observer<Key>(keyID: key.id) { [weak self] in
            self?.objectWillChange.send()
        }

        let observation = StoreObservation(
            store: store,
            key: key,
            observer: observer
        )

        // A store can notify the observer before registration returns, and a subscriber can then select another key
        // or store, which starts a later registration. Releasing this one deregisters it.
        guard registration == registrationCount else {
            return
        }

        self.observation = observation
    }
}

// MARK: - StoreObservation Definition

private final class StoreObservation<Key> where Key: PersistentKeyProtocol {
    private let key: Key
    private let observer: Observer<Key>
    private let store: any PersistentKeyValueStore

    // MARK: Internal Initialization

    internal init(
        store: any PersistentKeyValueStore,
        key: Key,
        observer: Observer<Key>
    ) {
        self.key = key
        self.observer = observer
        self.store = store

        store.register(
            observer: observer,
            for: key,
            with: nil,
            and: #selector(Observer<Key>.didReceive(_:))
        )
    }

    // MARK: Deinitialization

    deinit {
        store.deregister(observer, for: key, context: nil)
    }
}

// MARK: - Observer Definition

private final class Observer<Key>: NSObject, ObservableObject where Key: PersistentKeyProtocol {
    internal let keyID: String
    internal let objectWillChange: @MainActor () -> Void
    
    // MARK: Internal Initialization
    
    internal init(
        keyID: String,
        objectWillChange: @escaping @MainActor () -> Void
    ) {
        self.keyID = keyID
        self.objectWillChange = objectWillChange
    }
    
    // MARK: NSObject Implementation
    
    /// - SeeAlso: https://forums.swift.org/t/crash-when-running-in-swift-6-language-mode/72431/2
    internal nonisolated override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey: Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        guard keyPath == nil || keyPath == keyID else {
            return
        }

        performOnMainIfNecessary(objectWillChange)
    }
    
    // MARK: Internal Instance Interface
    
    /// - SeeAlso: https://forums.swift.org/t/crash-when-running-in-swift-6-language-mode/72431/2
    @objc
    internal nonisolated func didReceive(_ notification: Notification) {
        guard
            #available(watchOS 9.0, *),
            NSUbiquitousKeyValueStore.changeNotification(notification, mayAffectKeyID: keyID)
        else {
            return
        }
                
        performOnMainIfNecessary(objectWillChange)
    }
    
    // MARK: Private Instance Interface
    
    private func performOnMainIfNecessary(_ action: @escaping @MainActor () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated(action)
        } else {
            DispatchQueue.main.async(execute: action)
        }
    }
}
