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
/// This class, and the ``PersistentKeyValueStore`` functions it relies upon, implement the two known ways to observe
/// `UserDefaults` and `NSUbiquitousKeyValueStore`. It is likely that other ``PersistentKeyValueStore`` implementations 
/// can be written under the same interface but that is not what it is optimized for. This lets us use
/// ``PersistentValue`` with  any type of ``PersistentKeyValueStore`` and simplifies many callsites that previously had
/// to be duplicated between those two known ``PersistentKeyValueStore`` implementations.
///
/// - Important: Using this class with `NSUbiquitousKeyValueStore` requires all local (i.e. in-app) mutations to be
///   performed through the ``PersistentKeyValueStore`` APIs, or ``PersistentValue``. There is no way to observe local
///   changes performed through the system APIs for `NSUbiquitousKeyValueStore`; notifications only exist for external
///   changes, and key-value observation does not work. We emit a custom notification for internal changes to emulate
///   the external system behavior.
@MainActor
public final class PersistentKeyUIObservableObject<Key>: ObservableObject where Key: PersistentKeyProtocol {
    /// The key being observed.
    public let key: Key

    /// The store that the key is being observed in.
    private var _store: (any PersistentKeyValueStore)?

    /// The registration lifetime for the current store.
    private var observation: StoreObservation<Key>?
    
    /// The object used for key-value and `NotificationCenter` observation.
    private var observer: Observer<Key>!
    
    // MARK: Public Initialization
    
    /// Creates a new observer for the given key in the given store.
    ///
    /// - Parameter store: The store to observe the key in.
    /// - Parameter key: The key to observe.
    public init(store: (any PersistentKeyValueStore)?, key: Key) {
        self.key = key
        
        _store = store
        
        observer = Observer(keyID: key.id) { [weak self] in
            self?.objectWillChange.send()
        }

        registerObserver(on: store)
    }
    
    // MARK: Public Instance Interface
    
    /// The store that the key is being observed in.
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
    public var value: Key.Value {
        get {
            assertStoreExists(_store)
            
            return _store?.get(key) ?? key.defaultValue
        }
        set {
            assertStoreExists(_store)
            
            objectWillChange.send()
            
            _store?.set(key, to: newValue)
        }
    }
    
    // MARK: Private Instance Interface
    
    private func assertStoreExists(_ store: (any PersistentKeyValueStore)?) {
        assert(store != nil, "Store should always be set on initialization or immediately after.")
    }
    
    private func registerObserver(on store: (any PersistentKeyValueStore)?) {
        guard let store else {
            return
        }

        observation = StoreObservation(
            store: store,
            key: key,
            observer: observer
        )
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
            let changedKeyIDs = notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String]
        else {
            return
        }
                
        guard changedKeyIDs.contains(keyID) else {
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
