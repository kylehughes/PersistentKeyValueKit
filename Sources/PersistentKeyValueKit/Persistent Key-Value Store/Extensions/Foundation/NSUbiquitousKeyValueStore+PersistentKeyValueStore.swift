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
    
    @inlinable
    public func deregister<Key>(
        _ observer: NSObject,
        for key: Key,
        context: UnsafeMutableRawPointer?
    ) where Key : PersistentKeyProtocol {
        // We use selector-based notification APIs that do not need to perform manual observation deregistration.
    }
    
    @inlinable
    public func register<Key>(
        observer target: NSObject,
        for key: Key,
        with context: UnsafeMutableRawPointer?,
        and selector: Selector
    ) where Key: PersistentKeyProtocol {
        NotificationCenter.default.addObserver(
            target,
            selector: selector,
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: self
        )
        
        NotificationCenter.default.addObserver(
            target,
            selector: selector,
            name: NSUbiquitousKeyValueStore.didChangeInternallyNotification,
            object: self
        )
    }
    
    // MARK: Internal Static Interface
    
    @usableFromInline
    internal static var changedKeysKey: AnyHashable {
        AnyHashable(NSUbiquitousKeyValueStoreChangedKeysKey)
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
                changedKeysKey: [
                    keyID,
                ],
            ]
        )
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
