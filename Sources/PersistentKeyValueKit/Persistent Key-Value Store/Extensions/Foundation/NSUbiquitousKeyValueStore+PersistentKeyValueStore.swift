//
//  NSUbiquitousKeyValueStore+PersistentKeyValueStore.swift
//  PersistentKeyValueKit
//
//  Created by Kyle Hughes on 6/11/22.
//

import Foundation

// MARK: - PersistentKeyValueStore Extension

@available(watchOS 9.0, *)
extension NSUbiquitousKeyValueStore: PersistentKeyValueStore {
    /// The notification that is posted when the value of a key changes internally.
    public static let didChangeInternallyNotification = NSNotification.Name(
        "NSUbiquitousKeyValueStore.DidChangeInternally"
    )

    /// The migration capability for this ubiquitous key-value store.
    public var migrationEndpoint: PersistentKeyValueMigrationEndpoint {
        PersistentKeyValueMigrationEndpoint(
            backend: UbiquitousKeyValueMigrationBackend(self)
        )
    }
    
    // MARK: Getting Values

    @inlinable
    public func get<Key>(_ key: Key) -> Key.Value where Key: PersistentKeyProtocol {
        key.get(from: self)
    }
    
    // MARK: Setting Values
    
    @inlinable
    public func set<Key>(_ key: Key, to value: Key.Value) where Key: PersistentKeyProtocol {
        key.set(to: value, in: self)
        
        Self.postInternalChangeNotification(for: key, from: self)
    }
    
    // MARK: Removing Values

    @inlinable
    public func remove<Key>(_ key: Key) where Key: PersistentKeyProtocol {
        key.remove(from: self)
        
        Self.postInternalChangeNotification(for: key, from: self)
    }
    
    // MARK: Observing Keys
    
    public func deregister<Key>(
        _ observer: NSObject,
        for key: Key,
        context: UnsafeMutableRawPointer?
    ) where Key : PersistentKeyProtocol {
        StoreKeyObservationRegistry.registry(for: self).remove(observer, keyID: key.id, context: context)
    }
    
    public func register<Key>(
        observer target: NSObject,
        for key: Key,
        with context: UnsafeMutableRawPointer?,
        and selector: Selector
    ) where Key: PersistentKeyProtocol {
        StoreKeyObservationRegistry.registry(for: self).insert(
            UbiquitousKeyValueStoreKeyObservation(
                observer: target,
                keyID: key.id,
                context: context,
                selector: selector,
                store: self
            )
        )
    }
    
    // MARK: Internal Static Interface
    
    /// Returns whether a change notification from this store may have changed the value for `keyID`.
    ///
    /// Apple permits external change notifications without a changed-keys list, and an account change replaces every
    /// value in the local store, so both are treated as changes to every key.
    internal static func changeNotification(_ notification: Notification, mayAffectKeyID keyID: String) -> Bool {
        let userInfo = notification.userInfo

        if userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int == NSUbiquitousKeyValueStoreAccountChange {
            return true
        }

        guard let changedKeyIDs = userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] else {
            return true
        }

        return changedKeyIDs.contains(keyID)
    }

    @usableFromInline
    internal static func postInternalChangeNotification<Key>(
        for key: Key,
        from ubiquitousKeyValueStore: NSUbiquitousKeyValueStore
    ) where Key: PersistentKeyProtocol {
        postInternalChangeNotification(for: key.id, from: ubiquitousKeyValueStore)
    }
    
    @usableFromInline
    internal static func postInternalChangeNotification(
        for keyID: String,
        from ubiquitousKeyValueStore: NSUbiquitousKeyValueStore
    ) {
        NotificationCenter.default.post(
            name: didChangeInternallyNotification,
            object: ubiquitousKeyValueStore,
            userInfo: [
                NSUbiquitousKeyValueStoreChangedKeysKey: [
                    keyID,
                ],
            ]
        )
    }
}

// MARK: - UbiquitousKeyValueStoreKeyObservation Definition

/// Forwards a store's change notifications for one key to a registered observer's selector.
///
/// - Important: This type is manually `Sendable` because notifications are delivered on the posting thread. Its stored
///   properties are immutable after initialization, and `observer` is a weak reference.
@available(watchOS 9.0, *)
private final class UbiquitousKeyValueStoreKeyObservation: NSObject, StoreKeyObservation, @unchecked Sendable {
    let context: UnsafeMutableRawPointer?
    let keyID: String
    private(set) weak var observer: NSObject?
    private let selector: Selector

    // MARK: Internal Initialization

    init(
        observer: NSObject,
        keyID: String,
        context: UnsafeMutableRawPointer?,
        selector: Selector,
        store: NSUbiquitousKeyValueStore
    ) {
        self.context = context
        self.keyID = keyID
        self.observer = observer
        self.selector = selector

        super.init()

        for name in [
            NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            NSUbiquitousKeyValueStore.didChangeInternallyNotification,
        ] {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(didReceive(_:)),
                name: name,
                object: store
            )
        }
    }

    // MARK: StoreKeyObservation Implementation

    func invalidate() {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: Private Instance Interface

    @objc
    private func didReceive(_ notification: Notification) {
        guard
            let observer,
            NSUbiquitousKeyValueStore.changeNotification(notification, mayAffectKeyID: keyID)
        else {
            return
        }

        _ = observer.perform(selector, with: notification)
    }
}

// MARK: - Static Accessors

@available(watchOS 9.0, *)
extension PersistentKeyValueStore where Self == NSUbiquitousKeyValueStore {
    // MARK: Public Static Interface
    
    /// A convenient way to access `NSUbiquitousKeyValueStore.default`.
    @inlinable
    public static var ubiquitous: Self {
        .default
    }
}
